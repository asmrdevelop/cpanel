
# cpanel - Whostmgr/Transfers/Systems/Subaccount.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Transfers::Systems::Subaccount;

use strict;
use base 'Whostmgr::Transfers::Systems';
use Whostmgr::UserManager ();

sub get_prereq {
    return [ 'Homedir', 'Shell' ];
}

# There is no distinction needed between restricted and unrestricted restore
# here. No system-level data is being managed based on anything in the restored
# data. All we're doing is clearing out some of the cPanel user's data that's
# no longer applicable after a transfer.

*unrestricted_restore = \&restricted_restore;

sub restricted_restore {
    my ($self) = @_;
    my $user = $self->newuser;

    Whostmgr::UserManager::upgrade_if_needed(
        $user,
        {
            note           => $user,
            quiet          => 1,
            expire_invites => 1,
        }
    );

    return ( 1, 'Ran Subaccount database checks' );
}

1;
