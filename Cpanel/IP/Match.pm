package Cpanel::IP::Match;

# cpanel - Cpanel/IP/Match.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::IP::Expand ();

our %range_cache;
our %ip_bin_cache;

# ip_is_in_range
#
# Arguments:
# $ip is a valid IPv4 or IPv6 address
# $range is a range of IP addresses in CIDR format
#
# Returns:
# 1 - The IP Address is within the CIDR range.
# 0 - The IP Address is NOT within the CIDR range.
sub ip_is_in_range {
    my ( $ip, $range ) = @_;

    return 0 unless defined $range && length($range);

    my $ip_bin = ( $ip_bin_cache{$ip} ||= Cpanel::IP::Expand::ip2binary_string( Cpanel::IP::Expand::expand_ip( $ip, 6 ) ) );

    my ( $range_firstip_bin, $range_lastip_bin ) = @{ ( $range_cache{$range} ||= [ Cpanel::IP::Expand::first_last_ip_in_range($range) ] ) };

    return ( $ip_bin ge $range_firstip_bin && $range_lastip_bin ge $ip_bin ) ? 1 : 0;
}

sub ips_are_equal {
    my ( $first_ip, $second_ip ) = @_;

    my $first_ip_bin  = Cpanel::IP::Expand::ip2binary_string( Cpanel::IP::Expand::expand_ip( $first_ip,  6 ) );
    my $second_ip_bin = Cpanel::IP::Expand::ip2binary_string( Cpanel::IP::Expand::expand_ip( $second_ip, 6 ) );
    return 1 if $first_ip_bin eq $second_ip_bin;
    return 0;
}

1;
