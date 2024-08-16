package Cpanel::Server::HTTP;

# cpanel - Cpanel/Server/HTTP.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hostname ();

=encoding utf-8

=head1 NAME

Cpanel::Server::HTTP - HTTP Utilities for cPanel Servers

=head1 SYNOPSIS

    use Cpanel::Server::HTTP;

    Cpanel::Server::HTTP::setup_http_host( $untrusted_http_host_header_from_client );

    print $ENV{'HTTP_HOST'};

=cut

=head2 setup_http_host

Parse a http host header and set the HOST, HTTP_HOST, and SERVER_NAME ENV variables from it.

=head3 Input

=over

=item C<SCALAR>

    The http host header from the client.

=back

=head3 Output

Returns 1 and sets the $ENV vars

=cut

sub setup_http_host {
    my ($input_host) = @_;
    my ( $clean_host, $clean_port, $is_ipv6 ) = parse_http_host($input_host);

    # If IPv6 address. wrap the HTTP_HOST in bracket notation
    @ENV{ 'HTTP_HOST', 'HOST', 'SERVER_NAME' } = ( ( $is_ipv6 ? ( '[' . $clean_host . ']' ) : ($clean_host) ), ($clean_host) x 2 );
    return 1;
}

=head2 parse_http_host

Parses the Host: header from the client

=head3 Input

=over

=item C<SCALAR>

    The http host header from the client.

=back

=head3 Output

Returns a list of the following:

=over

=item C<SCALAR>

  The validated host

=item C<SCALAR>

  The validated port (if provided)

=item C<SCALAR>

  1 or 0 depending on if the host is an ipv6 address

=back

=cut

sub parse_http_host {
    my ($input_host) = @_;
    my $host_header = '';
    my $clean_host;
    my $clean_port;

    # Reject $input_host (Host: header) with invalid characters
    if ( length $input_host && $input_host !~ tr{a-zA-Z0-9.:[]-}{}c ) {
        $host_header = $input_host;
    }
    my $colon_cnt = $host_header =~ tr/://;
    if ( $colon_cnt > 1 ) {

        # IPv6 address with brackets and port
        if ( $host_header =~ m/^\[([a-zA-Z0-9\:]+)\]\:([0-9]+)/ ) {
            $clean_host = $1;
            $clean_port = $2;

            # IPv6 address with just brackets
        }
        elsif ( $host_header =~ m/^\[([a-zA-Z0-9\:]+)\]$/ ) {
            $clean_host = $1;

            # IPv6 address without brackets
        }
        elsif ( $host_header =~ m/^([a-zA-Z0-9\:]+)$/ ) {
            $clean_host = $1;
        }
    }
    elsif ( $colon_cnt < 2 ) {

        # IPv4 address or domain name with port
        if ( $host_header =~ m/^([a-zA-Z0-9\-.]+)\:([0-9]+)/ ) {
            $clean_host = $1;
            $clean_port = $2;

            # IPv4 address or domain name without port
        }
        elsif ( $host_header =~ m/^([a-zA-Z0-9\-.]+)$/ ) {
            $clean_host = $1;
        }
    }

    $clean_host ||= Cpanel::Hostname::gethostname();

    return ( $clean_host, $clean_port, $colon_cnt > 1 ? 1 : 0 );
}

1;
