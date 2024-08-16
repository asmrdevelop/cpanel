package Cpanel::Server::Response;

# cpanel - Cpanel/Server/Response.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::Server::LogAccess';

use Cpanel::Time::HTTP                        ();
use Cpanel::Exception                         ();
use Cpanel::Encoder::URI                      ();
use Cpanel::Encoder::HTTP                     ();
use Cpanel::Server::Responders::Stream        ();    # PPI USE OK -- used dynamically by _generate_responder
use Cpanel::Server::Responders::Stream::Gzip  ();    # PPI USE OK -- used dynamically by _generate_responder
use Cpanel::Server::Responders::Chunked       ();    # PPI USE OK -- used dynamically by _generate_responder
use Cpanel::Server::Responders::Chunked::Gzip ();    # PPI USE OK -- used dynamically by _generate_responder

use Parse::MIME ();

our $DEFAULT_DOCUMENT_EXPIRE_TIME = 86400;
our $MINIMUM_GZIP_SIZE            = 500;

########################################################
#
# Method:
#   new
#
# Description:
#   Creates a request object for a Cpanel::Server::Response
#   object
#
# Parameters:
#   logs         - A Cpanel::Server::Logs object
#   (required)
#
#   connection   - A Cpanel::Server::Connection object
#   (required)
#
#   request   - A Cpanel::Server::Request object
#   (required)
#
#
# Returns:
#   A Cpanel::Server::Response object
#
sub new {
    my ( $class, %OPTS ) = @_;

    # logs, connection required
    # user, pass optional
    return bless {
        '_sent_headers_to_socket' => 0,
        '_logs'                   => ( $OPTS{'logs'}       || die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'logs' ] ) ),
        '_connection'             => ( $OPTS{'connection'} || die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'connection' ] ) ),
        '_request'                => ( $OPTS{'request'}    || die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'request' ] ) ),
        '_xframeoptions'          => $OPTS{'xframecpsrvd'} // 1,
        '_is_trial'               => $OPTS{'_is_trial'},
    }, $class;
}

##
#
# Prunes all but the core keys from the object
#
# When adding new keys in the constructor, you must also add them
# here, otherwise children may not get a full "new" copy
##
sub start_new_request {
    delete @{ $_[0] }{ grep { $_ ne '_logs' && $_ ne '_connection' && $_ ne '_request' && $_ ne '_xframeoptions' } keys %{ $_[0] } };
    $_[0]->{'_sent_headers_to_socket'} = 0;
    return 1;
}

sub has_sent_headers_to_socket {
    return $_[0]->{'_sent_headers_to_socket'};
}

sub set_state_sent_headers_to_socket {
    return ( $_[0]->{'_sent_headers_to_socket'} = 1 );
}

sub _http10_keep_alive_response_headers {
    return "Connection: Keep-Alive\r\nKeep-Alive: timeout=" . $_[0]->{'_connection'}->get_keepalive_timeout() . ", max=200\r\n";
}

sub _x_frame_options_header {

    my $document = $_[0]->{'_request'}->get_document();

    return '' if ( ( defined $document ) and ( index( $document, './unprotected/loader.html' ) == 0 ) );    # skip for the load checkers

    if ( exists $_[0]->{'_xframeoptions'} && $_[0]->{'_xframeoptions'} != 0 ) {
        return "X-Frame-Options: SAMEORIGIN\r\nX-Content-Type-Options: nosniff\r\n";
    }

    return '';
}

sub download_content_type_headers {
    my ( $self, $content_type, $filename ) = @_;

    my $android_safe_filename = Cpanel::Encoder::HTTP::android_safe_filename($filename);
    return qq{Content-type: $content_type; name="$android_safe_filename"\r\n} . $self->content_disposition_download_header($filename);

}

sub content_disposition_download_header {
    my ( $self, $filename ) = @_;
    my $request_user_agent = $self->{'_request'}->get_header('user-agent');

    if ( $request_user_agent && $request_user_agent =~ m{MSIE [78]} ) {
        my $uri_encoded_filename = Cpanel::Encoder::URI::uri_encode_str($filename);
        return qq{Content-Disposition: attachment; filename="$uri_encoded_filename"\r\n};
    }
    else {
        my $uri_encoded_filename  = Cpanel::Encoder::URI::uri_encode_str($filename);
        my $android_safe_filename = Cpanel::Encoder::HTTP::android_safe_filename($filename);
        if ( $request_user_agent && $request_user_agent =~ m{android}i ) {
            return qq{Content-Disposition: attachment; filename="$android_safe_filename"\r\n};
        }
        else {
            return qq{Content-Disposition: attachment; filename="$android_safe_filename"; filename*=UTF-8''$uri_encoded_filename\r\n};
        }
    }
}

sub send_response {
    my ( $self, $response_source, $close_before_logging ) = @_;

    my $entire_content_is_in_memory = $response_source->entire_content_is_in_memory();

    if ( !$entire_content_is_in_memory && !$response_source->{'input_handle'} ) {
        die "Content must be in memory if no input_handle is provided";
    }

    my $responder_obj         = $self->_generate_responder($response_source);
    my $document              = $self->{'_request'}->get_document();
    my $document_is_streaming = defined($document) && index( $document, q{/live_} ) > -1 ? 1 : 0;

    $self->{'_connection'}->presend_object() if !$document_is_streaming;

    # Usually mmaped data
    if ( $response_source->buffer_is_read_only() ) {
        $responder_obj->readonly_from_input_and_send_response();
    }

    # Usually data coming from a remote sock (ie FPM) or an open file handle
    elsif ( $entire_content_is_in_memory || !$response_source->{'input_handle'} || !$response_source->{'input_handle'}->can('blocking') ) {
        $responder_obj->blocking_read_from_input_and_send_response();
    }

    # Usually data coming from a subprocess
    else {
        $responder_obj->nonblocking_read_from_input_and_send_response();
    }

    $response_source->{'input_handle'}->close() if $close_before_logging;

    $self->set_state_sent_headers_to_socket();
    $self->{'_connection'}->set_is_last_request(1) if !$responder_obj->sent_complete_content();

    my $is_last_request = $self->{'_connection'}->get_is_last_request();

    if ( !$document_is_streaming ) {

        # case CPANEL-3436:
        # If we do not remove the TCP_CORK before shutting down
        # the connection, browsers will get a connection
        # reset by peer error
        #
        $self->{'_connection'}->postsend_object();
    }

    if ($is_last_request) {
        $self->{'_connection'}->shutdown_connection();
    }

    $self->{'_connection'}->logger()->logaccess();

    # Return of 1 means we can serve another request on this connection
    # Return of 0 means we need to close the socket
    return $is_last_request ? 0 : 1;
}

sub _generate_responder {
    my ( $self, $response_source ) = @_;

    my $request_obj = $self->{'_request'};

    my $fields  = $response_source->get_fields();
    my $headers = $request_obj->get_headers();

    my $use_gzip = (
        ( $headers->{'accept-encoding'} || '' ) =~ m{gzip}i         &&       # client advertised gzip compatibility
          !$fields->{'content-encoding'}                            &&       # proposed response isn't already encoded
          !$fields->{'location'}                                    &&       # proposed response isn't a redirect
          substr( $request_obj->get_document() // '', -3 ) ne '.gz' &&       # requested resource isn't a .gz file
          _content_type_should_be_compressed( $fields->{'content-type'} )    # file is likely conducive to compression
    ) ? 1 : 0;

    #XXX FIXME UGLY HACK
    #The %ENV check is a holdover to get a fix out in v66;
    #v68 should see implementation of a cleaner fix.
    my $responder = $request_obj->get_protocol() > 1 && ( $use_gzip || !defined $response_source->{'content-length'} ) && !$ENV{'CP_SEC_WEBSOCKET_KEY'} ? 'Chunked' : 'Stream';

    #A bit of a kludge to get WebSocket working...
    if ( $headers->{'upgrade'} && index( $headers->{'upgrade'}, 'websocket' ) > -1 ) {
        $responder = 'Stream';
    }

    if ($use_gzip) {
        $responder .= '::Gzip';
    }

    #use Data::Dumper;
    #print STDERR "[$document][$responder]" . Dumper($response_source);
    my $connection_obj = $self->{'_connection'};
    return "Cpanel::Server::Responders::$responder"->new(
        'output_coderef'                  => sub { $connection_obj->write_buffer(@_) },
        'input_buffer'                    => $response_source->{'input_buffer'},
        'input_handle'                    => $response_source->{'input_handle'},
        'content-length'                  => $fields->{'content-length'},
        'input_handle_read_function_name' => $response_source->input_handle_read_function_name(),
        'read_size'                       => $response_source->read_size(),
        'headers_buffer'                  => $self->_generate_http_headers_for_source_responder( $response_source, $responder ),
    );
}

sub _content_type_should_be_compressed {
    my $content_type = shift;
    my ( $type, $subtype ) = Parse::MIME::parse_mime_type($content_type);

    return ( $type eq 'text' || $subtype =~ /(?:html|xml|json)/ || ( $type eq 'application' && $subtype eq 'x-tar' ) || ( $type eq 'image' && $subtype eq 'x-icon' ) );
}

sub _generate_http_headers_for_source_responder {
    my ( $self, $response_source ) = @_;

    my $fields           = $response_source->get_fields();
    my $http_status_code = $fields->{'http-status'}         || 200;
    my $status_message   = $fields->{'http-status-message'} || 'OK';
    my $location         = $fields->{'location'};
    my $content_type     = $fields->{'content-type'};
    my $last_modified    = $fields->{'last-modified'};

    if ( $location && $http_status_code == 200 ) {

        # redirects with a 200 status code are invalid. Some cPanel provided CGI binaries may
        # not send a valid Status: line though.
        $http_status_code = '307';
        $status_message   = 'Moved OK';
    }
    $ENV{'HTTP_STATUS'} = $http_status_code;

    my $now      = time();
    my $protocol = $self->{'_request'}->get_protocol();
    return \(
        ( $protocol eq '1.1'                                ? 'HTTP/1.1'                          : 'HTTP/1.0' ) . " $http_status_code $status_message\r\n"                         #
          . ( $self->{'_connection'}->get_is_last_request() ? "Connection: close\r\n"             : ( $protocol eq '1.0' ? $self->_http10_keep_alive_response_headers() : '' ) )    #
          . ( $location                                     ? "Location: $location\r\n"           : '' )                                                                            #
          . ( $content_type                                 ? "Content-Type: $content_type\r\n"   : '' )                                                                            #
          . ( $last_modified                                ? "Last-Modified: $last_modified\r\n" : '' )                                                                            #
          . "Date: " . Cpanel::Time::HTTP::time2http($now) . "\r\n"                                                                                                                 #
          . ( $fields->{'headers'} || '' )                                                                                                                                          #
          . $self->_get_document_dependant_headers( $response_source, $now )                                                                                                        #
          . $self->_x_frame_options_header()                                                                                                                                        #
          . $self->_runtime_header()                                                                                                                                                #
          . "\r\n"                                                                                                                                                                  #
    );
}

# Legacy
sub _get_document_dependant_headers {
    my ( $self, $response_source, $now ) = @_;

    return '' if index( ( scalar ref $response_source ), 'SubProcess' ) > -1;

    my $document     = $self->{'_request'}->get_document();
    my $content_type = $response_source->content_type();

    return '' unless defined $document;

    if ( index( $document, '/live_' ) > -1 ) {
        return "Cache-Control: no-cache, no-store, private, must-revalidate\r\nPragma: no-cache\r\n";
    }
    elsif (
           index( $document, 'munin/' ) == -1
        && index( $document, 'tmp/' ) == -1
        && (
            index( $document, '/cPanel_magic_revision_' ) > -1
            || (   index( $content_type, 'image/' ) == 0
                || index( $content_type, 'text/javascript' ) == 0
                || index( $content_type, 'text/css' ) == 0
                || index( $content_type, 'application' ) == 0
                || index( $content_type, 'font' ) == 0 )
        )
    ) {
        my $expire_time = $DEFAULT_DOCUMENT_EXPIRE_TIME * 60;
        return "Cache-Control: max-age=$expire_time, public\r\n" . 'Expires: ' . Cpanel::Time::HTTP::time2http( $now + $expire_time ) . "\r\n";
    }
    return '';
}

sub _runtime_header {
    my ($self) = @_;

    if ( $self->{'_is_trial'} ) {
        return "Server: cpsrvd [trial]\r\n";
    }
    return "";
}

1;
