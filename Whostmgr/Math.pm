package Whostmgr::Math;

# cpanel - Whostmgr/Math.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# figure "largest" possible non-exponential or just stick with
# 999_999_999_999_999 or whatever is the safest "high" one to use
my $largest_int      = 999_999_999_999_999;
my $default_int      = 999_999_999_999_990;    # different default number ?
my $large_int_format = '%.0f';                 # better format ?

sub unsci { goto &get_non_exponential_int; }

sub get_largest_int {
    return $largest_int;
}

sub get_default_int {
    return $default_int;
}

sub get_non_exponential_int {
    my ($n) = @_;
    return 0 if !$n;

    return $n if $n eq 'unlimited';

    if ( $n > $largest_int ) {
        $n = sprintf( $large_int_format, $n );
    }

    # regex needs checked for all possible permuataion of e-int-string
    elsif ( $n =~ m{\A[+-]?\d+(?:\.\d+)?[Ee][+-]?\d+\z} ) {
        $n = sprintf( $large_int_format, $n );
    }

    if ( $n > $largest_int ) {
        $n = $default_int;
    }

    return $n;
}

1;
