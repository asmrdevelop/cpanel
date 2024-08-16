package Whostmgr::Accounts::Suspension::DynamicWebContent;

# cpanel - Whostmgr/Accounts/Suspension/DynamicWebContent.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Suspension::DynamicWebContent

=head1 DESCRIPTION

This module unblocks dynamic web content on unsuspension.

It currently does nothing on suspension.

=cut

#----------------------------------------------------------------------

use Cpanel::ConfigFiles     ();
use Cpanel::SafeRun::Object ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 suspend()

Does nothing; exists solely to satisfy an interface.

=cut

sub suspend { return }

=head2 unsuspend($USERNAME)

Unblocks dynamic web content for the user. This is relevant for
accounts that were transferred under “Express Transfer” mode.

(For “Live Transfer” mode we don’t do the blocking in the first place
because HTTP service proxying obviates any use for it.)

=cut

sub unsuspend ( $username, @ ) {
    Cpanel::SafeRun::Object->new_or_die(
        program => "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/xfertool",
        args    => [
            '--unblockdynamiccontent',
            $username,
        ],
    );

    return;
}

1;
