package Cpanel::IP::Expand;

# cpanel - Cpanel/IP/Expand.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::IP::v4     ();
use Cpanel::Validate::IP::Expand ();

sub expand_ip {
    my ( $ip, $version ) = @_;

    $ip =~ tr{ \r\n\t}{}d if defined $ip;

    # This is the "render an IPv4 address within an IPv6 context"
    # clause, where the caller has given a v4 address, but explicitly
    # requested a v6 context.
    if ( defined $version && $version eq 6 && Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
        my @ipv4 = map { $_ + 0 } split /\./, $ip;
        return "0000:0000:0000:0000:0000:ffff:" . sprintf( '%04x', ( $ipv4[0] << 8 ) + $ipv4[1] ) . ':' . sprintf( '%04x', ( $ipv4[2] << 8 ) + $ipv4[3] );
    }

    # expand_ip returns undef if not valid so no need to check
    # if it valid before sending it of in order to avoid the
    # double valid check
    my $expanded = Cpanel::Validate::IP::Expand::expand_ip($ip);

    return $expanded if $expanded;

    # We got an invalid address.  We will return a zero address in
    # all failures.  We'll try to get the version right, at least.
    if ( defined $version && $version eq 6 || $ip =~ m/:/ ) {
        return '0000:0000:0000:0000:0000:0000:0000:0000';
    }
    return '0.0.0.0';
}

# AKA inet6_aton
#Takes a "human" address (e.g., '1.2.3.4')
#and returns e.g.: '00000001000000100000001100000100'
sub ip2binary_string {
    my $ip = shift || '';

    #IPv6
    if ( $ip =~ tr/:// ) {
        $ip = expand_ip( $ip, 6 );
        $ip =~ tr<:><>d;
        return unpack( 'B128', pack( 'H32', $ip ) );
    }

    #IPv4
    return unpack( 'B32', pack( 'C4C4C4C4', split( /\./, $ip ) ) );
}

#This accepts CIDR notation and outputs a binary string ("0010111...").
#
sub first_last_ip_in_range {
    my ($range) = @_;

    my ( $range_firstip, $mask ) = split( m{/}, $range );

    if ( !length $mask ) {
        die "Invalid input ($range) -- must be CIDR!";
    }

    my $mask_offset = 0;

    if ( $range_firstip !~ tr/:// ) {    # match as if it were an embedded ipv4 in ipv6
        $range_firstip = expand_ip( $range_firstip, 6 );
        $mask_offset   = ( 128 - 32 );                     # If we convert the range from ipv4 to ipv6 we need to move the mask
    }

    my $size = 128;

    my $range_firstip_binary_string = ip2binary_string($range_firstip);
    my $range_lastip_binary_string  = substr( $range_firstip_binary_string, 0, $mask + $mask_offset ) . '1' x ( $size - $mask - $mask_offset );

    return ( $range_firstip_binary_string, $range_lastip_binary_string );
}

1;
