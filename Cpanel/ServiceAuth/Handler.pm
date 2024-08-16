
# cpanel - Cpanel/ServiceAuth/Handler.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ServiceAuth::Handler;

use Cpanel::ServiceAuth ();
use Cpanel::WebService  ();

sub get_service_auth_port {
    my $self = shift;
    if ( open( my $srv_auth, '<', '/var/cpanel/serviceauth/' . $self->{'service'} . '/port' ) ) {
        local $/;
        return readline($srv_auth);
    }
    return;
}

sub handleserviceauth {

    my $self   = shift;
    my $socket = shift;

    alarm(35);
    local $SIG{'ALRM'} = sub {
        die "Service Auth timed out";
    };
    my $getreq = Cpanel::WebService::read_socket_headers($socket);

    return $self->process_request( $socket, $getreq );
}

sub process_request {
    my ( $self, $socket, $getreq ) = @_;

    my ($sendkey) = $getreq =~ /sendkey=([^&\s]+)/;

    my $keyok = 0;
    if ( $sendkey && $sendkey eq $self->fetch_sendkey() ) {
        $keyok = 1;
    }
    print {$socket} ( $keyok ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 401 Key Failed\r\n" ) . "Server: $self->{'service'}-dormant\r\nConnection: close\r\nContent-type: text/plain\r\n\r\n" . ( $keyok ? $self->fetch_recvkey() : "key not accepted\n" );
    if ( !$keyok ) {
        print STDERR "$0: failed request to service auth!\n";
        return 0;
    }
    return 1;
}

*Cpanel::ServiceAuth::get_service_auth_port = *get_service_auth_port;
*Cpanel::ServiceAuth::handleserviceauth     = *handleserviceauth;
*Cpanel::ServiceAuth::process_request       = *process_request;

1;
