package Cpanel::SafeRun::BG;

# cpanel - Cpanel/SafeRun/BG.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SafeRun::FDs ();

sub nooutputsystembg {
    my (@unsafecmd) = @_;

    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    my @cmd;
    while ( $unsafecmd[$#unsafecmd] eq '' ) { pop(@unsafecmd); }
    foreach (@unsafecmd) {
        my @cmds = split( / /, $_ );
        foreach (@cmds) { push( @cmd, $_ ); }
    }

    my $pid = fork();
    die "fork() failed: $!" if !defined $pid;

    if ( !$pid ) {
        Cpanel::SafeRun::FDs::setupchildfds();
        exec @cmd or exit 1;
    }

    return 1;
}

1;
