package Cpanel::Sys::IOStat;

# cpanel - Cpanel/Sys/IOStat.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Binaries        ();
use Cpanel::SafeRun::Simple ();

sub getiostat {
    local $ENV{'PATH'} = "/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/sbin:/bin";
    my @iostat = grep ( !m/^\s*$/, split( /\n/, Cpanel::SafeRun::Simple::saferun( Cpanel::Binaries::path('iostat') ) ) );

    shift @iostat;    # assume top line is generic system info

    return join( "\n", @iostat );
}

1;
