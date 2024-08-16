package Cpanel::Server::Handlers::SubProcess;

# cpanel - Cpanel/Server/Handlers/SubProcess.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: “subprocess_read_handle” must have an empty PerlIO buffer!
#----------------------------------------------------------------------

use cPstrict;
no warnings;    ## no critic qw(ProhibitNoWarnings)

use parent 'Cpanel::Server::Handler';

use Cpanel::App                                  ();
use Cpanel::AdminBin::Serializer                 ();
use Cpanel::FHUtils::Blocking                    ();
use Cpanel::FHUtils::Tiny                        ();
use Cpanel::Server::Response::Source::SubProcess ();
use Cpanel::HTTP::QueryString::Find              ();
use Cpanel::Server::Constants                    ();
use Cpanel::Alarm                                ();

my $AVERAGE_HTTP_RESPONSE_HEADER_SIZE = 850;
my $SUBPROCESS_READ_SIZE              = 65535;
my $FORCE_FAILURE                     = 1;

my $SUBPROCESS_READ_CHUNK_TIMEOUT = 360;

use constant KEYS_TO_ACCEPT => (
    'api_type',
    'subprocess_name',
    'subprocess_read_handle',
    'subprocess_write_handle',
    'subprocess_pid_to_reap',
);

sub handler {
    my ( $self, @opts_kv ) = @_;

    $self->_init_new_request(@opts_kv);

    my $server_obj = $self->get_server_obj();

    $self->_handle_content_length_for_subprocess();

    #XXX TODO FIXME: This module should really be two different classes:
    #one that accepts the FastCGI stuff, and the other that does plain CGI.
    #There isn’t time presently to split apart this module and add the proper
    #tests, though, so for now this will just have to be as-is.
    if ( $self->{'subprocess_read_handle'}->can('blocking') ) {
        $self->_read_headers_from_subprocess_non_blocking();
    }
    else {
        $self->_read_headers_from_subprocess_blocking();
    }

    #Note that Source::SubProcess is making the same assumptions about
    #an empty PerlIO read buffer that this module makes.
    my $response_source = Cpanel::Server::Response::Source::SubProcess->new(
        'entire_content_is_in_memory' => 0,
        'input_buffer'                => \$self->{'input_from_subprocess_buffer'},
        'input_handle'                => $self->{'subprocess_read_handle'},
    );
    my $has_headers = $response_source->parse_and_consume_headers( \$self->{'input_from_subprocess_buffer'} );

    if ( !$has_headers ) {
        if ( $response_source->get('location') ) {

            # A compliant CGI application should send enough of a response to be handled as normal CGI,
            # but the pre-11.30 handling of CGI responses allowed a Location: header by itself to be
            # treated as a redirect. If we saw a Location header and it wasn't handled as a full CGI response,
            # default to the old redirect behavior.
            $self->{'subprocess_read_handle'}->close();

            return $server_obj->docmoved( $response_source->get('location'), $response_source->get('headers') );

        }
        elsif ( $self->{'subprocess_read_handle'}->eof() ) {
            return $self->_shutdown_failed_subprocess();
        }
        else {
            $server_obj->connection()->write_buffer( $server_obj->fetchheaders( $Cpanel::Server::Constants::FETCHHEADERS_DYNAMIC_CONTENT, $Cpanel::Server::Constants::HTTP_STATUS_OK, $Cpanel::Server::Constants::FETCHHEADERS_SKIP_LOGACCESS ) );

            $server_obj->response()->set_state_sent_headers_to_socket();
        }
    }

    if ( $server_obj->{'CPCONF'}{'log-http-requests'} && !$response_source->get('content-type') && $response_source->get('headers') !~ m{^Connection:}im ) {
        $server_obj->get_log('request')->info("$ENV{'REQUEST_URI'} failed to set a Content-Type or Connection header.");
    }

    # If the handle is not perl open'ed sub process that will
    # that will auto wait pid on close, we close it right
    # after we have sent the response.
    my $this_child_can_serve_another_http_request = $server_obj->response()->send_response( $response_source, $self->{'subprocess_pid_to_reap'} );

    $self->_waitpid_if_have_pid() // do {

        # In the event the handle is a perl open'ed sub process that will
        # auto wait pid on close, we
        # Always close  $self->{'subprocess_read_handle'} at the last possible moment in order to give the subprocess
        # time to globally destruct so we are waiting for it the least amount of time
        $self->{'subprocess_read_handle'}->close();

    };

    $self->_report_subprocess_errors() if $? != 0;

    return $this_child_can_serve_another_http_request;
}

sub _init_new_request {
    my ( $self, %OPTS ) = @_;

    $self->{'api_version'} = undef;
    @{$self}{ KEYS_TO_ACCEPT() } = @OPTS{ KEYS_TO_ACCEPT() };

    # RDR was input_handle (subprocess_read_handle)
    # WTR was output_handle (subprocess_write_handle)

    return 1;
}

sub _handle_content_length_for_subprocess {
    my ($self) = @_;
    if ( $self->{'subprocess_write_handle'} ) {
        if ( index( $self->{'subprocess_name'}, '(uapi)' ) > -1 ) {
            $self->{'api_version'} = 3;

            my $form_ref = $self->get_server_obj()->timed_parseform();
            Cpanel::AdminBin::Serializer::DumpFile( $self->{'subprocess_write_handle'}, {%$form_ref} );
        }
        else {
            my $parsed = $self->_write_content_length_to_subprocess();
            $self->{'api_version'} = $parsed->{'api_version'};
        }

        $self->{'subprocess_write_handle'}->close();
    }
    return;
}

sub _read_headers_from_subprocess_blocking {
    my ($self) = @_;

    $self->{'input_from_subprocess_buffer'} = '';

    my $bytes;

    while ( !$self->{'subprocess_read_handle'}->eof() ) {
        $bytes = $self->{'subprocess_read_handle'}->read( $self->{'input_from_subprocess_buffer'}, $AVERAGE_HTTP_RESPONSE_HEADER_SIZE, length $self->{'input_from_subprocess_buffer'} );

        if ($bytes) {
            last if index( $self->{'input_from_subprocess_buffer'}, "\r\n\r\n" ) > -1 || index( $self->{'input_from_subprocess_buffer'}, "\n\n" ) > -1;
            next if $bytes == $AVERAGE_HTTP_RESPONSE_HEADER_SIZE;                                                                                         # ready to read again right away
        }
        else {
            warn "blocking read error: [$!]" if !defined $bytes;
            last;
        }
    }

    return;
}

sub _read_headers_from_subprocess_non_blocking {
    my ($self) = @_;

    #----------------------------------------------------------------------
    # We assume here that “subprocess_read_handle” has an empty PerlIO
    # read buffer. We could clear it out (e.g.,
    # Cpanel::FHUtils::flush_read_buffer()), but that’s a bit wasteful given
    # that we can ensure ourselves that the buffer is empty before we get here.
    #----------------------------------------------------------------------

    my $rin = Cpanel::FHUtils::Tiny::to_bitmask( $self->{'subprocess_read_handle'} );

    my $rout;
    my $ret;

    my $prev_blocking = Cpanel::FHUtils::Blocking::is_set_to_block( $self->{'subprocess_read_handle'} );
    Cpanel::FHUtils::Blocking::set_non_blocking( $self->{'subprocess_read_handle'} );

    $self->{'input_from_subprocess_buffer'} = '';
    local $!;
    while (1) {
        if ( -1 == select( $rout = $rin, undef, undef, undef ) ) {
            die "select(): $!" if $! && !$!{'EINTR'};
        }

        #This read() has to come before the select() because Perl may
        #likely have already buffered the headers.
        $ret = sysread( $self->{'subprocess_read_handle'}, $self->{'input_from_subprocess_buffer'}, $AVERAGE_HTTP_RESPONSE_HEADER_SIZE, length $self->{'input_from_subprocess_buffer'} );

        if ($ret) {
            last if index( $self->{'input_from_subprocess_buffer'}, "\r\n\r\n" ) > -1 || index( $self->{'input_from_subprocess_buffer'}, "\n\n" ) > -1;
            next if $ret == $AVERAGE_HTTP_RESPONSE_HEADER_SIZE;                                                                                           # ready to read again right away
        }
        elsif ( !defined $ret ) {

            #For some reason we’re getting $ret == undef and !$!
            #even though “perldoc -f read” says an undef return will set $!.
            last if !$!;

            if ( !$!{'EINTR'} && !$!{'EAGAIN'} ) {
                die "Failed to read from subprocess: $!";
            }
        }
        else {
            last;    # zero read without error
        }
    }

    if ($prev_blocking) {
        Cpanel::FHUtils::Blocking::set_blocking( $self->{'subprocess_read_handle'} );
    }

    return;
}

sub _shutdown_failed_subprocess {
    my ($self) = @_;
    my $server_obj = $self->get_server_obj();

    if ( !length $self->{'api_version'} ) {    # API 0 is valid
        $self->{'api_version'} = $self->_find_api_version_in_stringref( \$ENV{'QUERY_STRING'} ) || $self->_default_api_version();
    }

    # Always close  $self->{'subprocess_read_handle'} at the last possible moment in order to give the subprocess
    # time to globally destruct so we are waiting for it the least amount of time
    $self->{'subprocess_read_handle'}->close();

    $self->_waitpid_if_have_pid();

    $self->_report_subprocess_errors();

    $server_obj->logaccess();

    return 0;
}

sub _waitpid_if_have_pid ($self) {
    if ( $self->{'subprocess_pid_to_reap'} ) {
        waitpid( $self->{'subprocess_pid_to_reap'}, 0 );
        return $?;
    }

    return undef;
}

sub _report_subprocess_errors {
    my ($self) = @_;

    my $server_obj  = $self->get_server_obj();
    my $exit_msg    = $server_obj->exit_msg($?);
    my $http_status = ( $server_obj->upgrade_in_progress() ? $Cpanel::Server::Constants::HTTP_STATUS_SERVICE_UNAVAILABLE : $Cpanel::Server::Constants::HTTP_STATUS_INTERNAL_ERROR );

    my $id = do { srand(); substr( rand, 2 ) };

    $server_obj->get_log('error')->warn("The subprocess ($self->{'subprocess_name'}) exited with an error (ID $id): $exit_msg");

    if ( !$server_obj->response()->has_sent_headers_to_socket() ) {
        return $server_obj->handle_subprocess_failure( $http_status, $self->{'api_type'}, $self->{'api_version'}, "Internal Error (ID $id)" );
    }

    return $?;
}

#If $api_type is given, then this does some rudimentary parsing of the form
#data as it goes through and returns that information in a hashref:
#{
#   api_version => (version from form)
#}
sub _write_content_length_to_subprocess {
    my ($self) = @_;

    my $fh             = $self->{'subprocess_write_handle'};
    my $server_obj     = $self->get_server_obj();
    my $connection_obj = $server_obj->connection();
    my $api_version;

    my $need_api_version = $self->{'api_type'} && ( $self->{'api_type'} =~ m{-u?api} );
    my $socket           = $connection_obj->get_socket();
    if ( $server_obj->request()->get_header('content-length') ) {
        my $do_log_chunks = ( $server_obj->{'CPCONF'}{'log-http-requests'} && $server_obj->{'CPCONF'}{'log-http-requests-postdata'} );

        my $previous_chunk_sr  = \q{};
        my $bytes_left_to_read = int( $server_obj->request()->get_header('content-length') );
        my $bytes_read         = 0;

        if ( !$need_api_version ) {
            $api_version = 'unneeded';    #placeholder
        }

        my $alarm = Cpanel::Alarm->new( $SUBPROCESS_READ_CHUNK_TIMEOUT, sub { $server_obj->internal_error("The subprocess ($self->{'subprocess_name'}) failed to send content during the allowed timeframe."); } );

        local $!;
        while ( $bytes_left_to_read > 0 ) {
            my $current_chunk;

            $bytes_read = $socket->read( $current_chunk, $SUBPROCESS_READ_SIZE > $bytes_left_to_read ? $bytes_left_to_read : $SUBPROCESS_READ_SIZE );

            if ( !$bytes_read ) {
                undef $alarm;
                $connection_obj->pipehandler();
            }

            $bytes_left_to_read -= $bytes_read;

            print {$fh} $current_chunk or warn "Failed to write form data to subprocess: $!";

            if ($do_log_chunks) {
                my $request_count = $connection_obj->get_request_count();
                $server_obj->get_log('request')->info("[_write_content_length_to_subprocess $request_count]: $current_chunk") or warn "Failed to log form data: $!";
            }

            #
            # Note: for speed $api_version will be set to 'unknown'
            # if we do not need to look it up.  We only need to lookup
            # the api version if $need_api_version is set above in
            # this function.
            #
            # Currently we only need to know the api version so we produce
            # the correct error on failure for xml-api, json-api, and uapi.
            #
            if ( !length $api_version ) {
                $api_version = $self->_find_api_version_in_stringref( \"$$previous_chunk_sr$current_chunk" );

                if ( !length $api_version ) {
                    local $@;
                    eval {
                        substr( $current_chunk, 0, -50 ) = q{};    #50 is arbitrary but must be longer than $form_key below
                    };

                    $previous_chunk_sr = \$current_chunk;
                }
            }

            $alarm->set($SUBPROCESS_READ_CHUNK_TIMEOUT);
        }

        #Shouldn’t be necessary, but just in case.
        undef $alarm;
    }

    return { api_version => $need_api_version ? $api_version : undef };
}

sub _find_api_version_in_stringref {
    my ( $self, $haystack_sr ) = @_;

    my $form_key;
    if ( $self->_this_is_whm() ) {
        $form_key = 'api.version';
    }
    elsif ( $ENV{'SCRIPT_URI'} =~ m{\A\.?/xml-api/} ) {
        $form_key = 'cpanel_xmlapi_version';
    }
    else {
        $form_key = 'cpanel_jsonapi_version';
    }

    return Cpanel::HTTP::QueryString::Find::value_in_query_string( $form_key, $haystack_sr );
}

sub _this_is_whm {
    my ($self) = @_;

    return ( index( $Cpanel::App::appname, 'wh' ) > -1 ) ? 1 : 0;
}

sub _default_api_version {
    my ($self) = @_;
    return $self->_this_is_whm() ? 0 : 2;
}
1;
