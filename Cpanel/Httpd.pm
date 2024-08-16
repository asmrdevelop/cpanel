package Cpanel::Httpd;

# cpanel - Cpanel/Httpd.pm                         Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic(RequireUseWarnings) -- needs sufficient auditing for warnings cleanliness

use Cpanel::Gzip::Stream                    ();
use Cpanel::Time::HTTP                      ();
use Cpanel::Net::SSLeay::MultiDelimitReader ();
use Cpanel::HTTPDaemonApp                   ();
use Cpanel::Time::Clf                       ();
use HTTP::Request                           ();
use HTTP::Headers                           ();
use HTTP::Message                           ();
use Cpanel::CPAN::Net::SSLeay::Fast         ();
use Cpanel::Time::Local                     ();
use Cpanel::SV                              ();

use Errno qw[EINTR];

my $op_alarm_time = 360;
my $buffer_size   = 131070;

BEGIN {
    # Required to force and autoload and avoid a redefinition warning in
    # compiled code.
    eval { HTTP::Message->header; };
}

# Exim compatibility note:
# We should not use any modules that load any non perl default modules
# cPanelfunctions is out of the question here

sub new {
    my ( $obj, %OPTS ) = @_;
    my $self = {};
    $self->{'socket'}       = $OPTS{'socket'};
    $self->{'NetSSLeayobj'} = $OPTS{'NetSSLeayobj'};
    $self->{'SSLsocket'}    = $OPTS{'SSLsocket'};
    bless $self;
    return $self;
}

sub last_request {
    my $self = shift;
    return ( $self->{'_lastrequest'} ? 1 : 0 );
}

sub force_last_request {
    my $self = shift;
    $self->{'_lastrequest'} = 1;
}

sub send_response {
    my $self = shift;
    my $res  = shift;
    my $now  = shift || time();

    if ( $self->{'debug'} ) {
        require Data::Dumper;
        print STDERR "[$$] RESPONSE: " . Data::Dumper::Dumper($res);
        print STDERR "[$$] RESPONSE USAGE: " . `ps u -p $$`;
    }

    my $socket       = $self->{'socket'};
    my $code         = $res->code;
    my $message      = $res->message;
    my $response_txt = "HTTP/1.1 $code " . $message . "\r\n" . "Date: " . Cpanel::Time::HTTP::time2http($now) . "\r\n" . "Server: cPanel\r\nPersistent-Auth: false\r\n";    #must send Persistent-Auth false for windows 7

    if ( $ENV{'HTTP_HOST'} ) {
        $response_txt .= "Host: $ENV{'HTTP_HOST'}:$ENV{'SERVER_PORT'}\r\n";
    }

    # For Vista/Windows 7 (but not for ActiveSync or Caldav/Carddav)
    if ( exists $ENV{SERVER_PORT} && $ENV{SERVER_PORT} != 2091 && $ENV{SERVER_PORT} != 2080 && $ENV{SERVER_PORT} != 2079 ) {
        $res->headers->header( 'Cache-Control' => 'no-cache, no-store, must-revalidate, private' );
        $res->headers->header( 'Expires'       => 'Fri, 01 Jan 1990 00:00:00 GMT' );
        $res->headers->header( 'Vary'          => 'Accept-Encoding' );
    }

    my $content = $res->content();
    my $gziped_response;

    # CPANEL-20899: Cyberduck does not play nice with gzip and we don't know why
    # so disable gzip support for it
    if ( $self->{'can_gzip'} && ref($content) ne 'CODE' && index( $ENV{'HTTP_USER_AGENT'}, 'Cyberduck' ) == -1 ) {
        Cpanel::Gzip::Stream::gzip( \$content, \$gziped_response );
    }

    if ( defined $res->{'_length'} ) {
        if ( $self->{'debug'} ) {
            print STDERR "_length hack used\n";
        }
        if ( $res->{'_length'} == -1 ) {    #chunked
            $res->remove_header('Content-Length');
        }
        elsif ( defined $gziped_response ) {
            $res->headers->header( 'Content-Length'   => int( length $gziped_response ) );
            $res->headers->header( 'Content-Encoding' => 'gzip' );
        }
        elsif ( !ref $content ) {
            $res->headers->header( 'Content-Length' => int( length($content) ) );
        }
        else {
            $res->headers->header( 'Content-Length' => int( $res->{'_length'} ) );
        }
    }

    if ( defined $res->headers->header('content-length') && $res->headers->header('content-length') >= 0 ) {

        # content length is known
        my $cl;
        if ( defined $gziped_response ) {
            $cl = length $gziped_response;
            $res->headers->header( 'Content-Encoding' => 'gzip' );
        }
        else {
            $cl = ref $content ? $res->headers->header('content-length') : length $content;
        }

        $res->headers->header( 'Content-Length' => int $cl );
        if ( $self->{'debug'} ) {
            print STDERR "Content-Length: " . int($cl) . "\n";
        }
    }
    elsif ( $res->{'_length'} != -1 ) {

        # content length is unknown and response is not chunked
        if ( $self->{'debug'} ) {
            print STDERR "Unknown Content-Length, Closing connection\n";
        }
        $self->force_last_request();
    }

    $res->headers->header( 'Connection' => ( $self->last_request ? 'close' : 'Keep-Alive' ) );

    if ( ref $content eq 'CODE' ) {

        #       syswrite(STDERR,"CODE RESPONSE:" . $response_txt . $res->headers_as_string("\r\n") . "\r\n" . "\n");
        $self->write_socket( $response_txt . $res->headers_as_string("\r\n") . "\r\n" );
        $res->content->($self);
    }
    elsif ( defined $gziped_response ) {
        $self->write_socket( $response_txt . $res->headers_as_string("\r\n") . "\r\n" . $gziped_response );
    }
    else {

        # WARNING: Do not separate this line. Combining it appears to have
        # fixed the issue with Mac OS X Finder not connecting securely to
        # a webdisk.
        #    syswrite(STDERR,"FIXED RESPONSE:" . $response_txt . $res->headers_as_string("\r\n") . "\r\n" . $res->content . "\n");
        my $full_response = $response_txt . $res->headers_as_string("\r\n") . "\r\n" . $content;
        $self->write_socket($full_response);
    }
    return;
}

sub read_sslsocket_headers {
    my $self = shift;
    my ( $getreq, $header_ref );
    my $reqhandler_headers;
    my $NetSSLeayobj = $self->{'NetSSLeayobj'};
    if ( $self->{'debug'} ) {
        syswrite( STDERR, "[$$][" . Cpanel::Time::Clf::time2clftime() . "]:" . "reading headers from sslsocket at: " . __LINE__ . "\n" );
    }
    ( $getreq, $reqhandler_headers ) = split( /\r?\n/, Cpanel::Net::SSLeay::MultiDelimitReader::ssl_read_until_multi( $NetSSLeayobj, [ "\r\n\r\n", "\n\n" ], 2000000 ), 2 );    #this is our homebrew function which will eventually be uploaded to CPAN once I have time to write the POD -jnk

    if ( !$getreq ) {
        Cpanel::HTTPDaemonApp::kill_connection( $self, $self->{'socket'} );
    }
    $header_ref = parse_headers( \$reqhandler_headers );
    return ( $getreq, $header_ref );
}

sub parse_headers {
    my $reqhandler_headers_ref = shift;

    # lc is ok here
    # UNOPTIMIZED VERSION
    # foreach ( split( /$line_end/, $reqhandler_headers ) ) {
    #    ( $header, $value ) = split( /:\s*/, $_, 2 );
    #    $header =~ tr/A-Z/a-z/;
    #    $HEADERS{$header} = substr($value,0,8190);
    # }
    return {
        map   { ( lc $_->[0], substr( $_->[1], 0, 8190 ) ) }    # lc the header and truncate the value to 8190 bytes
          map { [ ( split( /:\s*/, $_, 2 ) )[ 0, 1 ] ] }        # split header into name, value - and place into an arrayref for the next map to alter
          split( /\r?\n/, $$reqhandler_headers_ref )
    };    # split each header
}

sub read_socket_headers {
    my $self = shift;
    my ( $getreq, $header_ref );
    if ( $self->{'debug'} ) {
        syswrite( STDERR, "[$$][" . Cpanel::Time::Clf::time2clftime() . "]:" . "reading headers from socket at: " . __LINE__ . "\n" );
    }
    while ( !$getreq ) {
        $getreq = readline( $self->{'socket'} );
        if ($getreq) {
            if ( $getreq =~ /^[\r\n]*$/ ) {
                $getreq = '';
                next;
            }
            last;
        }
        Cpanel::HTTPDaemonApp::kill_connection( $self, $self->{'socket'} );
    }
    {
        local $/ = ( ( $getreq =~ tr/\r// ? "\r\n" : "\n" ) x 2 );
        my $reqhandler_headers = readline( $self->{'socket'} );
        $header_ref = parse_headers( \$reqhandler_headers );
    }
    $getreq =~ s/[\r\n]+$//;    #safe chmop GLOBAL
    return ( $getreq, $header_ref );
}

sub killconnection {
    my $self = shift;
    if ( my $socket = $self->{'socket'} ) {

        #make sure we flush out the socket.. this is very important as ajax stuff may fail otherwise
        $socket->flush();

        #now shutdown the entire socket
        $socket->close();
    }

    exit;
}

sub parse_request_headers {
    my $self = shift;
    alarm($op_alarm_time);
    my ( $socket, $SSLsocket, $NetSSLeayobj ) = ( $self->{'socket'}, $self->{'SSLSocket'}, $self->{'NetSSLeayobj'} );
    my ( $getreq, $header_ref );
    if ($NetSSLeayobj) {
        ( $getreq, $header_ref ) = $self->read_sslsocket_headers();
    }
    else {
        ( $getreq, $header_ref ) = $self->read_socket_headers();
    }

    #use Data::Dumper;
    #   syswrite( STDERR, "getreq:$getreq " . Dumper($header_ref) );
    my ( $requestmethod, $uri, $protocol ) = split( /\s+/, $getreq );
    $protocol = ( $protocol =~ /([\d\.]+)/ ? $1 : '1.0' );

    my $httphead = HTTP::Headers->new( %{$header_ref} );

    $ENV{'REQUEST_METHOD'} = $requestmethod;
    $ENV{'CONTENT_LENGTH'} = $httphead->header('content-length');

    $uri =~ s/\.\.\/+//g;
    Cpanel::SV::untaint($uri);

    $ENV{'REQUEST_URI'} = $uri;

    my $original_query_string = '';
    if ( $uri =~ /\?/ ) {
        ( $uri, $original_query_string ) = split( /\?/, $uri, 2 );
    }

    $ENV{'QUERY_STRING'}       = $original_query_string;
    $ENV{'ACCEPT_ENCODING'}    = $httphead->header('accept-encoding');
    $ENV{'TRANSFER_ENCODING'}  = $httphead->header('transfer-encoding');
    $ENV{'SCRIPT_URI'}         = $uri;
    $ENV{'HTTP_USER_AGENT'}    = substr( $httphead->header('user-agent'),     0, 2048 );
    $ENV{'HTTP_REFERER'}       = substr( $httphead->header('referer'),        0, 2048 );
    $ENV{'CONTENT_TYPE'}       = substr( $httphead->header('content-type'),   0, 4096 );
    $ENV{'CONTENT_LENGTH'}     = substr( $httphead->header('content-length'), 0, 4096 );
    $ENV{'HTTP_COOKIE'}        = substr( $httphead->header('cookie'),         0, 4096 * 4 );
    $ENV{'HTTP_AUTHORIZATION'} = substr( $httphead->header('authorization'),  0, 4096 * 4 );

    if ( $httphead->header('host') =~ m/:/ ) {
        ( $ENV{'HTTP_HOST'}, $ENV{'SERVER_PORT'} ) = split( /:/, $httphead->header('host') );
        setSSLvars() if $ENV{'SERVER_PORT'} eq '2078';
        setSSLvars() if $ENV{'SERVER_PORT'} eq '2080';
    }
    else {
        $ENV{'HTTP_HOST'} = substr( $httphead->header('host'), 0, 1024 );
    }
    $ENV{'SERVER_NAME'}     = $ENV{'HTTP_HOST'};
    $self->{'_contentread'} = 0;
    $self->{'uri'}          = $uri;

    if ( lc($requestmethod) ne 'get' && lc($requestmethod) ne 'put' ) {
        my $buffer;
        $self->{'_contentread'} = 1;
        if ( my $explanation = _request_too_long( $getreq, $httphead ) ) {
            print STDERR "DoS Protection Activated; $explanation\n";
            $self->force_last_request();
        }
        elsif ( int $httphead->header('content-length') > 0 ) {
            my $bytes_left_to_read = int $httphead->header('content-length');
            local $!;
            while ( $bytes_left_to_read && ( my $bytes_read = $socket->read( $buffer, $bytes_left_to_read, length $buffer ) ) ) {
                if ( $bytes_read == -1 ) {
                    next if ( $! == EINTR );    # got a signal in the middle of the read, start again
                    die "The system failed to read “$bytes_left_to_read” because of an error: $!\n";
                }
                $bytes_left_to_read -= $bytes_read;
            }
        }
        $self->{'httprequest'} = HTTP::Request->new( $requestmethod, $uri, $httphead, $buffer );
    }
    else {
        # For certain request methods, don't store request body directly in the HTTP::Request object.
        # Instead, store an accessor function that will read from the socket on demand and write
        # directly to the specified filehandle, thus bypassing the need for an intermediate variable.
        # Callers need to be aware that $request->content may be either a string or a code ref depending
        # on the request method.
        my $fetchcontent = sub {
            my ($write_to_fh) = @_;
            $self->processformdata($write_to_fh);
        };
        $self->{'httprequest'} = HTTP::Request->new( $requestmethod, $uri, $httphead, $fetchcontent );
    }

    # CPDAVD wipes the ENV, but we must have this available
    $self->{'original_query_string'} = $original_query_string;
    alarm($op_alarm_time);
    return 1;
}

sub _request_too_long {
    my ( $getreq, $httphead ) = @_;
    if ( substr( $getreq, 0, 33 ) eq 'POST /Microsoft-Server-ActiveSync' ) {
        if ( $getreq =~ /Cmd=SendMail/ ) {
            if ( int( $httphead->header('content-length') ) > 100 * 1024 * 1024 ) {    # TODO: BWG-2207 - Either lower this limit or make it configurable
                return 'ActiveSync SendMail request larger than 100M discarded';
            }
        }
        elsif ( int( $httphead->header('content-length') ) > 1 * 1024 * 1024 ) {
            return 'ActiveSync request larger than 1M discarded';
        }
    }
    elsif ( int $httphead->header('content-length') > 100000 ) {
        return 'Request larger than 100k discarded';
    }
    return '';
}

sub finish_request {
    my $self = shift;

    return if $self->{_contentread};
    return if not int $self->{httprequest}->headers->header('content-length');

    if ( $self->{'skip_formdata'} == 1 ) {
        return;
    }

    printf STDERR "[%s] Application Bug: there is still content data waiting on the incoming socket and we ignored it!\n",
      Cpanel::Time::Local::localtime2timestamp();

    return $self->processformdata();    # HBHB TODO - why is this here ? it has no $fh to write the data to ? it gets called on an unauthenticated POST request, why ?
}

sub processformdata {
    my $self     = shift;
    my $fh       = shift;
    my $socket   = $self->{'socket'};
    my $httphead = $self->{'httprequest'}->headers;
    $self->{'_contentread'} = 1;
    my $transfer_encoding = lc $httphead->header('transfer-encoding');
    if ( int $httphead->header('content-length') || ( $transfer_encoding && $transfer_encoding eq 'chunked' ) ) {
        my $formdata   = '';
        my $bytes_read = 0;
        my $cl         = int( $httphead->header('content-length') );
        if ( $transfer_encoding && $transfer_encoding eq 'chunked' ) {
            my $raw_chunk_length;
            my $chunk_length;
            my $new_cl = 0;
          CHUNKREAD:
            while (1) {
                alarm($op_alarm_time);
                $raw_chunk_length = readline($socket);
                if ( !defined $raw_chunk_length ) {
                    last CHUNKREAD;
                }
                $chunk_length = 0;
                if ( $raw_chunk_length =~ m/^([abcdefABCDEF\d]+)/ ) {
                    $chunk_length = hex($1);
                }
                if ( $chunk_length == 0 ) {
                    while (1) {
                        my $footer = readline($socket);
                        if ( !$footer || $footer =~ m/^[\r\n]*$/ ) {
                            last CHUNKREAD;
                        }
                    }
                }
                else {
                    $bytes_read = 0;
                    while ( $chunk_length > 0 ) {
                        if ( $chunk_length > $buffer_size ) {
                            $formdata   = '';
                            $bytes_read = 0;
                            my $bytes_left = $buffer_size;
                            while ( $bytes_read < $buffer_size ) {
                                $bytes_left -= ( $bytes_read += $socket->read( $formdata, $bytes_left, length $formdata ) );
                            }
                        }
                        else {
                            $bytes_read = $socket->read( $formdata, $chunk_length );
                        }
                        if ($bytes_read) {
                            $new_cl += $bytes_read;
                            if ($fh) { syswrite( $fh, $formdata ); }
                            $chunk_length -= $bytes_read;
                        }
                        else {
                            select( undef, undef, undef, 0.10 );
                        }
                    }
                    readline($socket);    #get the crlf out of the buffer
                }
            }
            $ENV{'CONTENT_LENGTH'} = $new_cl;
        }
        else {
            alarm($op_alarm_time);
            my $bytes_left = 0;
            while ( $cl > 0 ) {

                #                 if ( length $formdata < 1 ) {    # HBHB TODO - when cleaning up debugging, leave this logic to prevent a neverending loop
                #                     alarm(0);
                #                     last;
                #                 }
                if ( $cl > $buffer_size ) {
                    $formdata   = '';
                    $bytes_read = 0;
                    $bytes_left = $buffer_size;
                    while ( $bytes_read < $buffer_size ) {
                        $bytes_left -= ( $bytes_read += $socket->read( $formdata, $bytes_left, length $formdata ) );
                    }
                }
                else {
                    $bytes_read = $socket->read( $formdata, $cl );
                }
                if ($bytes_read) {
                    if ($fh) { syswrite( $fh, $formdata ); }
                    $cl -= $bytes_read;
                    alarm($op_alarm_time);
                }
                else {
                    #read failed, wait 0.10 seconds
                    select( undef, undef, undef, 0.10 );
                }
            }
        }
    }
    return;
}

sub setSSLvars {
    $ENV{'HTTPS'}                = 'on';
    $ENV{'SSL_PROTOCOL_VERSION'} = 3;
    return;
}

#
# Output an HTTP 1.1 Error based on the arguments. Assumes
# content encoding is already done.
#
# Arguments:
#   status    - number - HTTP Status Code
#   message - String - Message to send in the header
#   content - String - Document to send with the response.
#   server  - String - Server name, defaults to cPanel.
#
sub send_error {
    my ( $self, $status, $message, $content, $server ) = @_;

    $message ||= 'Error';
    $content ||= '';
    $server  ||= 'cPanel';

    return $self->write_socket( "HTTP/1.1 $status $message\r\n" . "Date: " . Cpanel::Time::HTTP::time2http( time() ) . "\r\n" . "Server: $server\r\n" . "Content-Length: " . length($content) . "\r\n" . "\r\n" . $content );
}

#
# write_socket
#
# Write a buffer to the socket with the most efficient code
# path we have
#
# Arguments:
#   $buffer - a scalar or scalar reference to write to the socket
#
sub write_socket {
    my ( $self, $buffer ) = @_;

    # For debug
    # use Data::Dumper;
    # print STDERR Carp::longmess("[write_socket][" . Dumper($buffer) . "]") . "\n";
    if ( $self->{'NetSSLeayobj'} ) {
        return Cpanel::CPAN::Net::SSLeay::Fast::ssl_write_all( $self->{'NetSSLeayobj'}, $buffer );

        # ssl_write_all does the error checking for us
    }
    my $bytes_written = 0;

    # We support passing as a reference or a non-reference to be compatible with ssl_write_all
    my $ref_buffer = ref $buffer ? $buffer : \$buffer;

    my $total_length = length $$ref_buffer;
    my $bytes_written_this_loop;
    local $!;
    while ( $bytes_written_this_loop = syswrite( $self->{'socket'}, $$ref_buffer, ( $total_length - $bytes_written ), $bytes_written ) ) {
        if ( $bytes_written_this_loop == -1 ) {
            next if ( $! == EINTR );    # got a signal in the middle of the write, start again
            my $bytes_attempted_to_write = ( $total_length - $bytes_written );
            die "The system failed to write “$bytes_attempted_to_write” because of an error: $!\n";
        }

        $bytes_written += $bytes_written_this_loop;

        last if ( $total_length - $bytes_written ) == 0;
    }
    return $bytes_written;
}

1;
