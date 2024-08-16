package Whostmgr::Services::dovecot;

# cpanel - Whostmgr/Services/dovecot.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::LoadFile ();

our $DOVECOT_MASTER_PID_FILE = '/var/run/dovecot/master.pid';

sub reload_service {
    my $master_pid = Cpanel::LoadFile::loadfile($DOVECOT_MASTER_PID_FILE);
    if ( kill( 'HUP', $master_pid ) > 0 ) {
        return;
    }

    # have to discard output here since the '--verbose' flag
    # is enabled by default in the restartsrv scripts
    system '/usr/local/cpanel/scripts/restartsrv_dovecot --reload 1>/dev/null';
    return;
}

1;
