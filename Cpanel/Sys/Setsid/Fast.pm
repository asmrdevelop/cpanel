package Cpanel::Sys::Setsid::Fast;

# cpanel - Cpanel/Sys/Setsid/Fast.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my $ALREADY_GAVE_UP_TTY = 0;
my $TIOCNOTTY           = 0x5422;

# Fast and cheap setsid like behavior.
# Does not fully daemonize, but should work for most cases.
sub fast_setsid {
    setpgrp( 0, 0 );
    return if $ALREADY_GAVE_UP_TTY;
    open( my $tty, '+<', '/dev/tty' ) or do {
        $ALREADY_GAVE_UP_TTY = 1;
        return 0;    # if we can't open /dev/tty then we don't need to do anything.
    };
    ioctl( $tty, $TIOCNOTTY, 0 ) or die "Unable to ioctl on /dev/tty: $!";
    close $tty;
    return 1;
}

1
