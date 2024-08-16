package Cpanel::IP::Utils;

# cpanel - Cpanel/IP/Utils.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#This allows you to check whether an IP address (IPv4 or IPv6) is private.
#It returns the number of mask bits that match a pattern for a
#private IP address; e.g., '192.168.1.1' returns 16,
#while '10.2.3.4' returns 8.
#
#Anything else returns undef.
#
#This does NOT validate. Behavior from an invalid IP address
#is undefined.
#
sub get_private_mask_bits_from_ip_address {
    my ($addr) = @_;
    die "Need address!" if !$addr;

    return 8  if rindex( $addr, '10.',      0 ) == 0;
    return 16 if rindex( $addr, '192.168.', 0 ) == 0;

    return 7 if $addr =~ m<\A[fF][cCdD]>;

    return 12 if $addr =~ m<\A172\.(([0-9])|([1-9][0-9]{0,2}))\.> && $1 >= 16 && $1 <= 31;

    return undef;
}

1;
