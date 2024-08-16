package Cpanel::UUID::Server;

# cpanel - Cpanel/UUID/Server.pm                   Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DIp::MainIP;
use Cpanel::NAT;

=head1 NAME

Cpanel::UUID

=head1 DESCRIPTION

Functions to generate UUIDs that are not completely random, but tied to the main server IP. This may
not fully comply with RFC 4122, but is good enough for Cpanel to uniquely identify a server.

=head1 FUNCTIONS

=head2 get_server_uuid()

This is a variation of Cpanel::UUID::random_uuid. The generated UUID is not random, but tied to the
main ip of the server.

=head3 RETURNS

UUID generated using the server IP as seed.

=cut

my $uuid;

sub get_server_uuid {
    return $uuid if $uuid;

    my $ip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainip() );

    my @ip_parts = split( /\./, $ip );
    my $seed     = $ip_parts[0] * 1000000000 + $ip_parts[1] * 1000000 + $ip_parts[2] * 1000 + $ip_parts[3];
    srand($seed);

    my $random_data = '';
    my $chars_ar    = [ 0 .. 9, 'A' .. 'Z', 'a' .. 'z', '_' ];
    my $num_chars   = @$chars_ar;
    $random_data .= $chars_ar->[ rand $num_chars ] for ( 1 .. 16 );
    srand;

    # Setting these bits this way is required by RFC 4122.
    vec( $random_data, 35, 2 ) = 0x2;
    vec( $random_data, 13, 4 ) = 0x4;

    return $uuid = join "-", unpack( "H8 H4 H4 H4 H12", $random_data );
}

sub _clear_uuid {
    $uuid = undef;
    return;
}

1;
