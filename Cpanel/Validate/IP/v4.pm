package Cpanel::Validate::IP::v4;

# cpanel - Cpanel/Validate/IP/v4.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# Note: this loop has been unrolled for speed
sub is_valid_ipv4 {
    my ($ip) = @_;
    return unless $ip;    # False scalars are never an _[0].

    my @segments = split /\./, $ip, -1;
    return unless scalar @segments == 4;

    my $octet_index;
    for my $octet_value (@segments) {
        return if !_valid_octet( $octet_value, ++$octet_index );
    }

    return 1;
}

sub is_valid_cidr4 {
    my ($ip) = @_;

    return unless defined $ip && $ip;
    my ( $ip4, $mask ) = split /\//, $ip;
    return if !defined $mask || !length $mask || $mask =~ tr/0-9//c;

    # Apparently, 32 is allowed as a mask.
    return is_valid_ipv4($ip4) && 0 < $mask && $mask <= 32;
}

sub _valid_octet {
    my ( $octet_value, $octet_index ) = @_;
    return (
        !length $octet_value                                                ||    #
          $octet_value =~ tr/0-9//c                                         ||    #
          $octet_value > 255                                                ||    #
          ( substr( $octet_value, 0, 1 ) == 0 && length($octet_value) > 1 ) ||    # Only dec values are permitted
          $octet_index == 1 && length($octet_value) && !$octet_value              # First oct can't be zero.
    ) ? 0 : 1;
}

1;
