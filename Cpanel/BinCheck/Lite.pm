package Cpanel::BinCheck::Lite;

# cpanel - Cpanel/BinCheck/Lite.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This module is provided for scripts which also have to function in a compiled form
# It is also used for scripts which we want to monitor basemem information on over time
# (i.e. daemons)

use strict;

sub check_argv {
    my $arg = $ARGV[0] or return;

    if ( $arg eq '--bincheck' ) {
        bincheck();    # exits.
        exit(0);
    }
    elsif ( $arg eq '--basemem' ) {
        basemem();     # exits
        exit(0);
    }

    return;
}

sub bincheck {
    print qq{BinCheck ok\n};
    return;
}

sub basemem {
    if ( open my $stats, '<', "/proc/$$/status" ) {
        while ( my $line = readline $stats ) {
            if ( index( $line, 'VmRSS:' ) > -1 && $line =~ m{([0-9]+)} ) {
                print qq{VmRSS (in KBytes): $1\n};
            }
        }
    }
    return;
}

1;
