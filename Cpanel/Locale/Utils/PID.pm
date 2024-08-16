package Cpanel::Locale::Utils::PID;

# cpanel - Cpanel/Locale/Utils/PID.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Unix::PID::Tiny ();    # this needs done in a use() for binaries

my $pid_obj;

sub build_locale_databases_is_running {
    open my $fh, '<', '/var/run/build_locale_databases.pid' or return;
    my $cont = readline($fh);
    close $fh;
    chomp($cont);
    if ( my $pid = int( abs($cont) ) ) {
        if ( !$pid_obj ) {
            $pid_obj = Cpanel::Unix::PID::Tiny->new();
        }

        return $pid_obj->is_pid_running($pid);
    }

    return;
}

1;
