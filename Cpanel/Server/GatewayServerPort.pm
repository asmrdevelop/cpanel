package Cpanel::Server::GatewayServerPort;

# cpanel - Cpanel/Server/GatewayServerPortion.pm               Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Server::HTTP ();
use Cpanel::IP::Loopback ();

=encoding utf-8

=head1 NAME

Cpanel::Server::GatewayServerPort - Tools to determine the port the http client is sending to

=head1 FUNCTIONS

=head2 $portnum = determine_SERVER_PORT( $HOST_HDR, \%CPCONF, \%PORTMAP )

Returns the value to assign to C<$ENV{'SERVER_PORT'}> based on the
received C<Host> HTTP header ($HOST_HDR) and cPanel’s configuration
(\%CPCONF). %PORTMAP is a map of non-SSL to SSL ports.

This is for contexts where it’s established that a gateway (aka
“reverse proxy”) sits between the client and the cPanel & WHM server.

Note that it’s more ideal for gateways to send this via the C<by>
component to the C<Forwarded> header
(cf. L<RFC 7239|https://tools.ietf.org/html/rfc7239>) than to use
a heuristic like this.

See also L<RFC 3875/4.1.15|https://tools.ietf.org/html/rfc3875#section-4.1.15>
for the definition of C<SERVER_PORT> for CGI applications.

=cut

my $env_https;

sub determine_SERVER_PORT {
    my ( $host_header, $cpconf_ref, $non_ssl_to_ssl_port_map ) = @_;

    my ( $parsed_host, $parsed_port ) = Cpanel::Server::HTTP::parse_http_host($host_header);

    $env_https = $ENV{'HTTPS'} // q<>;

    # Prioritize the Host header’s port, if given.
    #
    # Cloudflare may be proxying :2087 so we want to
    # set the SERVER_PORT to 2087 otherwise all whm
    # assets will fail to load
    if ( $parsed_port && !Cpanel::IP::Loopback::is_loopback($parsed_host) ) {

        # If the Host header’s port is a non-SSL port but
        # the request is SSL, then use the corresponding SSL port.
        if ( $env_https eq 'on' && $non_ssl_to_ssl_port_map->{$parsed_port} ) {

            # This is a special case
            # If https is on and we are going to a non-ssl port this means
            # its a proxy subdomain
            return ( ( split( ':', $cpconf_ref->{'apache_ssl_port'} // q<> ) )[-1] || 443 );
        }
        else {
            return $parsed_port;
        }
    }

    if ( $env_https eq 'on' ) {
        return ( ( split( ':', $cpconf_ref->{'apache_ssl_port'} // q<> ) )[-1] || 443 );
    }

    return ( ( split( ':', $cpconf_ref->{'apache_port'} // q<> ) )[-1] || 80 );
}

1;
