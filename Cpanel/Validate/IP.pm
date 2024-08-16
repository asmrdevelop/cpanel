package Cpanel::Validate::IP;

# cpanel - Cpanel/Validate/IP.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::IP::v4 ();

sub is_valid_ipv6 {
    my ($ip) = @_;
    return unless defined $ip && $ip;

    if (   ( substr( $ip, 0, 1 ) eq ':' && substr( $ip, 1, 1 ) ne ':' )
        || ( substr( $ip, -1, 1 ) eq ':' && substr( $ip, -2, 1 ) ne ':' ) ) {
        return;    # Can't have single : on front or back
    }

    my @seg = split /:/, $ip, -1;    # -1 to keep trailing empty fields

    # Clean up leading/trailing double colon effects.
    shift @seg if $seg[0] eq '';
    pop @seg   if $seg[-1] eq '';

    my $max = 8;
    if ( index( $seg[-1], '.' ) > -1 ) {
        return unless Cpanel::Validate::IP::v4::is_valid_ipv4( pop @seg );
        $max -= 2;
    }

    my $cmp;
    for my $seg (@seg) {
        if ( !defined $seg || $seg eq '' ) {

            # Only one compression segment allowed.
            return if $cmp;
            ++$cmp;
            next;
        }
        return if $seg =~ tr/0-9a-fA-F//c || length $seg == 0 || length $seg > 4;
    }
    if ($cmp) {

        # If compressed, we need at least 1, and up to and *including*
        # $max segments - a single segment can be compressed, so we'll
        # still have $max segments.
        return ( @seg && @seg <= $max ) && 1;    # true returned as 1
    }

    # Not compressed, all segments need to be there.
    return $max == @seg;
}

sub is_valid_ipv6_prefix {
    my ($ip) = @_;
    return unless $ip;
    my ( $ip6, $mask ) = split /\//, $ip;
    return unless defined $mask;
    return if !length $mask || $mask =~ tr/0-9//c;
    return is_valid_ipv6($ip6) && 0 < $mask && $mask <= 128;
}

# Is valid IP v4 or IP v6 address.
sub is_valid_ip {
    return !defined $_[0] ? undef : index( $_[0], ':' ) > -1 ? is_valid_ipv6(@_) : Cpanel::Validate::IP::v4::is_valid_ipv4(@_);
}

sub ip_version {
    return 4 if Cpanel::Validate::IP::v4::is_valid_ipv4(@_);
    return 6 if is_valid_ipv6(@_);
    return;
}

sub is_valid_ip_cidr_or_prefix {
    return unless defined $_[0];
    if ( $_[0] =~ tr/:// ) {
        return $_[0] =~ tr{/}{} ? is_valid_ipv6_prefix(@_) : is_valid_ipv6(@_);
    }
    return $_[0] =~ tr{/}{} ? Cpanel::Validate::IP::v4::is_valid_cidr4(@_) : Cpanel::Validate::IP::v4::is_valid_ipv4(@_);
}

sub is_valid_ip_range_cidr_or_prefix {
    my $str = shift;
    return 0 if !$str;
    return 1 if is_valid_ip_cidr_or_prefix($str);

    my @pieces = split /-/, $str, 2;
    return 1 if 2 == grep { defined($_) } map { Cpanel::Validate::IP::v4::is_valid_ipv4($_) } @pieces;
    return 1 if 2 == grep { defined($_) } map { is_valid_ipv6($_) } @pieces;
    return 0;
}

1;
