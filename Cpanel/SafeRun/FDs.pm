package Cpanel::SafeRun::FDs;

# cpanel - Cpanel/SafeRun/FDs.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::CleanupStub ();

sub setupchildfds {
    open( STDERR, '>', '/dev/null' ) or warn $!;
    open( STDIN,  '<', '/dev/null' ) or warn $!;

    open( STDOUT, '>', '/dev/null' ) or warn $!;

    closefds();
}

*closefds = \&Cpanel::CleanupStub::closefds;

1;
