package Cpanel::Wrap;

# cpanel - Cpanel/Wrap.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::AdminBin::Serializer ();

# This will already be loaded if it is neded
# do not include for memory
# use Cpanel                        ();
use Cpanel::Socket::Constants     ();
use Cpanel::Socket::UNIX::Micro   ();
use Cpanel::AdminBin::Utils::Exit ();

our $VERSION             = 1.4;
our $CPWRAPD_SOCKET_PATH = '/usr/local/cpanel/var/cpwrapd.sock';

my $logger;

# mocked in tests
sub _get_cpwrapd_connection {
    my %OPTS = @_;

    my $socket;
    my $s = socket(
        $socket,
        $Cpanel::Socket::Constants::AF_UNIX,
        $Cpanel::Socket::Constants::SOCK_STREAM,
        0,
    );
    warn "cpwrapd socket() failed: $!" if !$s;

    my $usock = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($CPWRAPD_SOCKET_PATH);

    if ( connect( $socket, $usock ) ) {
        return $socket;
    }

    my $message = "Cpanel::AdminBin::_get_cpwrapd_connection failed to connect to “$CPWRAPD_SOCKET_PATH”: $!";

    if ( !$OPTS{'no_cperror'} ) {
        $Cpanel::context ||= 'wrap';                      # PPI NO PARSE - Cpanel will be loaded if needed
        $Cpanel::CPERROR{$Cpanel::context} = $message;    # PPI NO PARSE - Cpanel will be loaded if needed
    }

    {
        local $!;
        _logger()->warn($message);
    }

    return;
}

# NOTE: We're trying to get away from setting $Cpanel::CPERROR. If we can
# get all the calls using this shim, we can remove the setting of $Cpanel::CPERROR
# and then remove this shim.
sub send_cpwrapd_request_no_cperror {
    my (%OPTS) = @_;

    $OPTS{'no_cperror'} = 1;

    return scalar send_cpwrapd_request(%OPTS);
}

sub send_cpwrapd_request {
    my (%OPTS) = @_;

    my $socket = _get_cpwrapd_connection() || return {
        'status'    => 0,
        'error'     => 1,
        'statusmsg' => "Failed to connect to cpsrvd socket “$CPWRAPD_SOCKET_PATH”: $!",
    };

    my ( $sent_ok, $response_sr, $stream ) = _send_request_over_socket( $socket, %OPTS );

    if ($stream) {
        return {
            'status'   => 1,
            'error'    => 0,
            'streamed' => 1,
        };
    }

    if ( !$response_sr ) {

        if ( !$sent_ok ) {
            _logger()->warn("Cpanel::AdminBin::send_cpwrapd_request received SIGPIPE and no response");
        }

        return {
            'status'    => 0,
            'error'     => 1,
            'statusmsg' => "No data returned from cpwrapd call: namespace=[$OPTS{'namespace'}] module=[$OPTS{'module'}] function=[$OPTS{'function'}]"
        };
    }

    if ( !$sent_ok ) {
        _logger()->warn("Cpanel::AdminBin::send_cpwrapd_request received SIGPIPE and still got a response");
    }

    my $ref = Cpanel::AdminBin::Serializer::Load($$response_sr);

    if ( ref $ref ) {
        my $exit_msg;

        if ( $ref->{'exit_code'} ) {
            my $exitcode = $ref->{'exit_code'};
            $exit_msg = Cpanel::AdminBin::Utils::Exit::exit_msg(
                $exitcode,
                {
                    'namespace' => ( $OPTS{'namespace'} || 'Cpanel' ),
                    'module'    => $OPTS{'module'},
                    'function'  => $OPTS{'function'}
                }
            );
            if ( !$OPTS{'no_cperror'} ) {
                _logger()->warn( __PACKAGE__ . "::send_cpwrapd_request $exit_msg: namespace=[$OPTS{'namespace'}] module=[$OPTS{'module'}] function=[$OPTS{'function'}]: set error in context $Cpanel::context: raw_response=[$$response_sr]" );    # PPI NO PARSE - Cpanel will be loaded if needed
                $Cpanel::CPERROR{$Cpanel::context} = _error_as_text( $exit_msg || 'send_cpwrapd_request unknown error' );                                                                                                                          # PPI NO PARSE - Cpanel will be loaded if needed
            }
            else {
                _logger()->warn( __PACKAGE__ . "::send_cpwrapd_request $exit_msg: namespace=[$OPTS{'namespace'}] module=[$OPTS{'module'}] function=[$OPTS{'function'}]: raw_response=[$$response_sr]" );
            }
        }
        if ( $ref->{'error'} ) {
            if ( !$OPTS{'no_cperror'} ) {
                _logger()->warn( __PACKAGE__ . "::send_cpwrapd_request error: namespace=[$OPTS{'namespace'}] module=[$OPTS{'module'}] function=[$OPTS{'function'}]: set error in context $Cpanel::context: statusmsg=[$ref->{'statusmsg'}]" );     # PPI NO PARSE - Cpanel will be loaded if needed
                $Cpanel::CPERROR{$Cpanel::context} = _error_as_text( $ref->{'data'} || $ref->{'statusmsg'} || $exit_msg || 'send_cpwrapd_request unknown error' );                                                                                 # PPI NO PARSE - Cpanel will be loaded if needed
            }
            else {
                _logger()->warn( __PACKAGE__ . "::send_cpwrapd_request error: namespace=[$OPTS{'namespace'}] module=[$OPTS{'module'}] function=[$OPTS{'function'}]: statusmsg=[$ref->{'statusmsg'}]" );
            }
        }

    }

    if ( !$ref ) {
        return {
            'status'    => 0,
            'error'     => 1,
            'statusmsg' => "Failed to deserialize data returned from cpwrapd call: namespace=[$OPTS{'namespace'}] module=[$OPTS{'module'}] function=[$OPTS{'function'}] data=[$$response_sr]"
        };

    }

    if ( $ref->{'status'} ) {
        $ref->{'response_ref'} = $response_sr;
    }

    return $ref;
}

sub _send_request_over_socket {
    my ( $socket, %OPTS ) = @_;

    my $response;
    my $sent_ok = 1;
    my $stream  = $OPTS{'stream'};
    my $nowait  = $OPTS{'nowait'};

    local $SIG{'PIPE'} = sub {
        $sent_ok = 0;
        return 1;
    };

    if ( $OPTS{'fdpass'} ) {
        require Cpanel::FDPass;
        Cpanel::FDPass::send( $socket, $OPTS{'fdpass'} );
    }

    my $request = Cpanel::AdminBin::Serializer::Dump(
        {
            'version'   => $Cpanel::AdminBin::Serializer::VERSION,
            'namespace' => $OPTS{'namespace'},
            'module'    => $OPTS{'module'},
            'function'  => $OPTS{'function'},
            'action'    => $OPTS{'action'},
            'env'       => $OPTS{'env'},
            'data'      => $OPTS{'data'},
        }
    ) . "\r\n\r\n";    #must end request with \r\n\r\n

    syswrite( STDERR,  "[send_cpwrapd_request][REQUEST]=[$request]\n" ) if $Cpanel::Debug::level > 2;    # PPI NO PARSE -- OK if module not loaded
    syswrite( $socket, $request ) or warn "syswrite() cpwrap: $!";
    shutdown( $socket, 1 );                                                                              #stopped writing

    # nowait is only suitable for requests that you want to launch in the background without waiting for a result
    if ($nowait) {
        return ( $sent_ok, \'{}', $stream );
    }
    elsif ($stream) {
        my $buf;
        require Cpanel::Autodie;
        require Cpanel::LoadFile::ReadFast;

        while ( Cpanel::Autodie::sysread_sigguard( $socket, $buf, Cpanel::LoadFile::ReadFast::READ_CHUNK() ) ) {
            Cpanel::Autodie::syswrite_sigguard( $stream, $buf );
        }
        if ($!) {
            warn "read() cpwrap stream: $!";
        }
    }
    else {
        local $/ = undef;

        $response = readline($socket);
        if ($!) {
            warn "read() cpwrap: $!";
        }
    }

    syswrite( STDERR, "[send_cpwrapd_request][RESPONSE]=[$response]\n" ) if $Cpanel::Debug::level > 2;    # PPI NO PARSE -- OK if module not loaded

    return ( $sent_ok, \$response, $stream );
}

sub _error_as_text {
    my ($obj) = @_;

    return $obj if !ref $obj;
    if ( ref $obj eq 'HASH' ) {
        return $obj->{'statusmsg'} || $obj->{'message'} || $obj->{'error'} || 'Unknown error';
    }
    if ( ref $obj eq 'ARRAY' ) {
        return $obj->[0];
    }
    return $obj;
}

sub _logger {
    return $logger if defined $logger;
    eval 'require Cpanel::Logger' or die "Failed to load Cpanel::Logger: $@";
    return ( $logger = 'Cpanel::Logger'->new() );
}

1;
