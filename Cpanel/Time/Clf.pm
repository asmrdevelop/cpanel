package Cpanel::Time::Clf;

# cpanel - Cpanel/Time/Clf.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub time2clftime {
    my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime( $_[0] || time() );
    return sprintf( '%02d/%02d/%04d:%02d:%02d:%02d -0000', $mon + 1, $mday, $year + 1900, $hour, $min, $sec );
}

sub time2utctime {
    my ( $sec, $min, $hour, $mday, $mon, $year ) = gmtime( $_[0] || time() );
    return sprintf( '%04d-%02d-%02dT%02d:%02d:%02d', $year + 1900, $mon + 1, $mday, $hour, $min, $sec );
}

sub time2isotime {
    return time2utctime( $_[0] ) . 'Z';
}

1;
