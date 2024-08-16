package Whostmgr::Sys;

# cpanel - Whostmgr/Sys.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::SafeRun::Simple ();

sub reboot {
    if ( fork() ) {

    }
    else {
        sleep 1;
        Cpanel::SafeRun::Simple::saferun('/sbin/reboot');
        exit 0;
    }
}

sub forcereboot {
    if ( fork() ) {

    }
    else {
        sleep 1;
        Cpanel::SafeRun::Simple::saferun( '/sbin/reboot', '-f' );
        exit 0;
    }
}

1;
