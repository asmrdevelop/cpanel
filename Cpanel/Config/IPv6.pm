package Cpanel::Config::IPv6;

# cpanel - Cpanel/Config/IPv6.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.1';
our ( $should_listen, $should_control );

sub should_listen {
    return defined $should_listen ? $should_listen : ( $should_listen = -e '/var/cpanel/ipv6_listen' ? 1 : 0 );
}

sub should_control {
    return defined $should_control ? $should_control : ( $should_control = -e '/var/cpanel/ipv6_control' ? 1 : 0 );
}

1;
