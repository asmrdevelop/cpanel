package Cpanel::IP::Loopback;

# cpanel - Cpanel/IP/Loopback.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub is_loopback {
    return (
        length $_[0]
          && (
            $_[0] eq 'localhost'                                          #
            || $_[0] eq 'localhost.localdomain'                           #
            || $_[0] eq '0000:0000:0000:0000:0000:0000:0000:0001'         #
            || index( $_[0], '0000:0000:0000:0000:0000:ffff:7f' ) == 0    # ipv4 inside of ipv6 match 127.*
            || index( $_[0], '::ffff:127.' ) == 0                         # ipv4 inside of ipv6 match 127.*
            || index( $_[0], '127.' ) == 0                                # ipv4 needs to match 127.*
            || $_[0] eq '0:0:0:0:0:0:0:1'                                 #
            || $_[0] eq ':1'                                              #
            || $_[0] eq '::1'                                             #
            || $_[0] eq '(null)'                                          #
            || $_[0] eq '(null):0000:0000:0000:0000:0000:0000:0000'       #
            || $_[0] eq '0000:0000:0000:0000:0000:0000:0000:0000'         #
            || $_[0] eq '0.0.0.0'
          )                                                               #
    ) ? 1 : 0;
}

1;
