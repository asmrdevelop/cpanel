package Cpanel::Sort::Utils;

# cpanel - Cpanel/Sort/Utils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Validate::IP::v4;
use Cpanel::Validate::IP;
use Cpanel::IPv6::Sort;

my %ipv4_cache;

# A private function, only to be used here.
# Note: Use of prototypes makes this slower than the private function.
sub _ipv4 {
    return ( $ipv4_cache{$a} ||= pack( 'CCCC', split( /\./, $a ) ) ) cmp( $ipv4_cache{$b} ||= pack( 'CCCC', split( /\./, $b ) ) );
}

sub sort_ip_list {
    my $ips_ar = ( 'ARRAY' eq ref $_[0] ) ? $_[0] : \@_;

    my @ipv4_addrs = grep { Cpanel::Validate::IP::v4::is_valid_ipv4($_) } @$ips_ar;
    @ipv4_addrs = sort _ipv4 @ipv4_addrs;

    my @ipv6_addrs = grep { Cpanel::Validate::IP::is_valid_ipv6($_) } @$ips_ar;
    Cpanel::IPv6::Sort::in_place( \@ipv6_addrs );

    $ips_ar = [ @ipv4_addrs, @ipv6_addrs ];

    return @$ips_ar;
}

sub sort_ipv4_list {
    my $ips_ar = ( 'ARRAY' eq ref $_[0] ) ? $_[0] : \@_;

    $ips_ar = [ sort _ipv4 @$ips_ar ];

    return wantarray ? @$ips_ar : $ips_ar;
}

# Sort by shallowest to deepest. Within same depth, sort lexicographically.
# Suppressing critic errors on this function because this is the documented way of
# writing a sorter. (perldoc -f sort)
sub _dirdepth {
    ( my $a_depth = $a ) =~ tr{/}{}dc;
    ( my $b_depth = $b ) =~ tr{/}{}dc;
    return ( ( length($a_depth) <=> length($b_depth) ) || ( $a cmp $b ) );
}

sub sort_dirdepth_list (@list) {

    return sort _dirdepth @list;
}

1;
