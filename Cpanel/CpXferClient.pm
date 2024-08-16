package Cpanel::CpXferClient;

# cpanel - Cpanel/CpXferClient.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::CpXferClient - client module for CpXfer protocol

=head1 DESCRIPTION

This module implements client logic for the “CpXfer” protocol, described
in L<Cpanel::Server::CpXfer>.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception       ();
use Cpanel::Locale          ();
use MIME::Base64            ();
use IO::Socket::SSL         ();
use Cpanel::Services::Ports ();
use Cpanel::Context         ();
##
##  This module was broken out of bin/whm_xfer_download-ssl.pl and only has minimal
##  refactoring.  It could stand to use some more cleanup in the future
##

our $DEFAULT_TIMEOUT = 15;
my $MAX_HEADER_READ_TIMEOUT = 180;    # 3 minutes to connect

my %SERVICE_AUTHZ_HEADER_KEYWORD = (
    whostmgr => 'WHM',
    cpanel   => 'cpanel',
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->new( %OPTS )

Instantiates the class. %OPTS are:

=over

=item * C<service> - One of: C<cpanel>, C<webmail>, or C<whostmgr>.
(Default is C<whostmgr>, but this default should not be relied upon.)

=item * C<host> - The cpsrvd hostname to connect to.

=item * C<user> - The username to use in authentication.

=item * C<pass> - The user’s password; used/required if and only if
C<accesshash> is not given.

=item * C<accesshash> - The WHM user’s accesshash; used/required if
and only if C<pass> is not given.

=item * C<timeout> - Timeout for the connection, in seconds.

=back

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    my $service = $OPTS{'service'} || 'whostmgr';    # legacy compat

    my $port;
    if ( $service eq 'cpanel' ) {
        $port = $OPTS{'disable_ssl'} ? $Cpanel::Services::Ports::SERVICE{'cpanel'} : $Cpanel::Services::Ports::SERVICE{'cpanels'};
    }
    elsif ( $service eq 'webmail' ) {
        $port = $OPTS{'disable_ssl'} ? $webmail::Services::Ports::SERVICE{'webmail'} : $webmail::Services::Ports::SERVICE{'webmails'};
    }
    else {
        $port = $OPTS{'disable_ssl'} ? $Cpanel::Services::Ports::SERVICE{'whostmgr'} : $Cpanel::Services::Ports::SERVICE{'whostmgrs'};
    }

    #This is provided for mocking a streaming server in tests.
    if ( $OPTS{'_port'} ) {
        $port = $OPTS{'_port'};
    }

    Net::SSLeay::load_error_strings();
    Net::SSLeay::OpenSSL_add_ssl_algorithms();
    Net::SSLeay::randomize();

    return bless {
        'port'        => $port,
        'disable_ssl' => $OPTS{'disable_ssl'} ? 1 : 0,
        'service'     => $service,
        'host'        => $OPTS{'host'},
        'user'        => $OPTS{'user'},
        'timeout'     => $OPTS{'timeout'},
        'pass'        => $OPTS{'pass'},
        'accesshash'  => $OPTS{'accesshash'},
    }, $class;
}

=head2 I<OBJ>->get_connection()

Connect to the remote cpsrvd server. An exception
(L<Cpanel::Exception::ConnectionFailed>) is thrown on failure.

=cut

sub get_connection {
    my ($self) = @_;

    my ( $host, $port, $timeout ) = @{$self}{qw(host port timeout)};

    $timeout ||= $DEFAULT_TIMEOUT;

    #Try a few times to connect to the server.
    my $module = $self->{'disable_ssl'} ? 'IO::Socket::INET' : 'IO::Socket::SSL';
    my $client;

    my $last_err;

    for ( 1 .. 2 ) {
        $client = $module->new( PeerHost => $host, PeerPort => $port, Timeout => $timeout, SSL_verify_mode => 0 ) and last;

        # The IO::Socket modules put the failure details into $@.
        $last_err = $@;

        sleep 1;
    }

    if ( !$client || !ref $client ) {
        die Cpanel::Exception::create( 'ConnectionFailed', "The [asis,WHM] client could not connect to “[_1]:[_2]” because of an error: [_3]", [ $host, $port, $last_err ] );
    }
    $client->timeout(0);
    $client->autoflush(1);
    $self->{'client'} = $client;
    return 1;
}

=head2 I<OBJ>->make_request()

Sends a request to the remote cpsrvd server.

L<Cpanel::Exception::IO::WriteError> is thrown on failure.

=cut

sub make_request {
    my ( $self, $url, $postdata ) = @_;

    my ( $user, $pass, $accesshash ) = @{$self}{qw( user pass accesshash)};
    my ( $host, $port, $timeout )    = @{$self}{qw(host port timeout)};
    my $client = $self->{'client'};
    my $refer  = "http" . ( $self->{'disable_ssl'} ? '' : 's' ) . "://$host:$port/";

    my $client_request = ( $postdata ? 'POST' : 'GET' ) . " $url HTTP/1.0\r\n";
    $client_request .= "Host: $host:$port\r\n";
    $client_request .= "Referer: $refer\r\n";
    $client_request .= "Connection: close\r\n";

    if ($postdata) {
        $client_request .= "Content-Length: " . length($postdata) . "\r\n";
    }

    if ($accesshash) {
        my $authz_hdr_keyword = $SERVICE_AUTHZ_HEADER_KEYWORD{ $self->{'service'} };

        if ( !$authz_hdr_keyword ) {
            die "No “Authorization” header keyword for service “$self->{'service'}”!";
        }

        $client_request .= ( "Authorization: $authz_hdr_keyword " . $user . ':' . $accesshash . "\r\n\r\n" );
    }
    else {
        require Cpanel::HTTP::BasicAuthn;
        my ( $hdr, $value ) = Cpanel::HTTP::BasicAuthn::encode( $user, $pass );
        $client_request .= "$hdr: $value\r\n\r\n";
    }

    $client_request .= $postdata if $postdata;
    syswrite( $client, $client_request ) or do {
        die Cpanel::Exception::create( 'IO::WriteError', 'The system failed to send a request to the remove server because of an error: [_1]', [$!] );
    };

    return 1;
}

=head2 $skt = I<OBJ>->get_socket()

Returns the object’s underlying socket as a Perl filehandle.

=cut

sub get_socket {
    my ($self) = @_;
    return $self->{'client'};
}

=head2 $skt = I<OBJ>->get_port()

Returns the TCP port on the remote cpsrvd server to which the
object will connect (or has connected).

=cut

sub get_port {
    my ($self) = @_;
    return $self->{'port'};

}

=head2 ( $tag, $content_length ) = I<OBJ->read_headers_from_socket()

Must be called in list context.

Reads the HTTP response headers from the object’s TCP socket.

Returns the values of the received C<X-Complete-Tag> and
C<Content-Length> HTTP headers.

=cut

sub read_headers_from_socket {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my $socket = $self->get_socket();
    my ( $tag, $content_length, $error_message );

    local ( $!, $^E );

    alarm($MAX_HEADER_READ_TIMEOUT);
    while ( readline($socket) ) {
        ## case 16718: communicate 401 status back to caller (notably whm5)
        alarm($MAX_HEADER_READ_TIMEOUT);

        if (m/^HTTP\/[0-9\.]+\s([0-9]+)\s(.*)/) {
            my $status_code = $1;
            my $status_msg  = "HTTP Status $1 - $2";
            chomp($status_msg) if length $status_msg;
            if ( $status_code !~ m{^2} ) {
                $error_message ||= $status_msg;
            }
        }
        elsif (/^content-length: (\d+)/i) {
            $content_length = $1;
        }
        elsif (/^X-Complete-Tag: (\S+)/i) {
            $tag = $1;
        }
        elsif (/^X-Error-Message: (.*+)/i) {
            $error_message = $1;
        }

        last if (/^[\r\n]*$/);
    }
    alarm(0);

    if ($!) {
        die Cpanel::Exception::create( 'IO::ReadError', 'The system failed to read from the remote [asis,cPanel] server because of an error: [_1]', [$!] );
    }
    elsif ($error_message) {
        die Cpanel::Exception->create_raw($error_message);
    }

    return ( $tag, $content_length );
}

=head2 $skt = I<OBJ>->connect_syncstream()

A convenience method that makes a syncstream connection, reads
(and discards) the headers, and returns the connection’s socket
(à la C<get_socket()>).

=cut

sub connect_syncstream {
    my ($self) = @_;

    $self->get_connection();

    $self->make_request('/syncstream?message=null');

    () = $self->read_headers_from_socket();

    return $self->get_socket();
}

=head2 $creds_hr = I<OBJ>->get_credentials()

Returns a hash reference with the following members:

=over

=item * C<host> and C<user> as given to the constructor.

=item * C<use_ssl>, C<service>, and C<accesshash> as the connection
will use them.

=back

=cut

sub get_credentials {
    my ($cpanel_client) = @_;
    return {
        'use_ssl' => $cpanel_client->{'disable_ssl'} ? 0 : 1,
        'host'    => $cpanel_client->{'host'},
        'user'    => $cpanel_client->{'user'},
        $cpanel_client->{'accesshash'} ? ( 'accesshash' => $cpanel_client->{'accesshash'} ) : ( 'pass' => $cpanel_client->{'pass'} ),
        'service' => $cpanel_client->{'service'},
    };
}

=head2 $ok = I<OBJ>->close()

Closes the connection’s underlying file handle.
The return value is that from Perl’s C<close()> built-in; C<$!> will
report any relevant failure.

=cut

sub close {
    my ($self) = @_;
    return $self->{'client'}->close();
}

1;
