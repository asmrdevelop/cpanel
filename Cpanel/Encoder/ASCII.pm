package Cpanel::Encoder::ASCII;

# cpanel - Cpanel/Encoder/ASCII.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub to_hex {
    my ($readable) = @_;

    $readable =~ s<\\><\\\\>g;
    $readable =~ s<([\0-\x{1f}\x{7f}-\x{ff}])><sprintf '\x{%02x}', ord $1>eg;

    return $readable;
}

1;
