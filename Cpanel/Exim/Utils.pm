package Cpanel::Exim::Utils;

# cpanel - Cpanel/Exim/Utils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my $base = 62;    # used to account for case-insensitive filesystems, where this needs to be 36.

my @tab62 = (
    ( (undef) x ord('0') ),
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  0,  0, 0, 0, 0, 0,    # 0-9
    0,  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,               # A-K
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,               # L-W
    33, 34, 35, 0,  0,  0,  0,  0,                                # X-Z
    0,  36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46,               # a-k
    47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58,               # l-w
    59, 60, 61                                                    # x-z
);

my %msg_id_cache;

# Logic for this taken from exiqgrep script
sub get_time_from_msg_id {
    my $id = substr( $_[0], 0, 6 );

    return $msg_id_cache{$id} if exists $msg_id_cache{$id};

    my $c;
    my $s = 0;
    for $c ( split m{}, $id ) {
        $s = $s * $base + $tab62[ ord $c ];
    }

    return $msg_id_cache{$id} = $s;
}

1;
