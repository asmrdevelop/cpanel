package Whostmgr::Transfers::Session::Items::BackupsRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/BackupsRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0.0';

use base qw(Whostmgr::Transfers::Session::Items::ConfigBackupBase Whostmgr::Transfers::Session::Items::Schema::BackupsRemoteRoot);

sub module_info {
    my ($self) = @_;

    return {
        'item_name'            => 'Backups',
        'config_module'        => 'cpanel::system::backups',
        'config_restore_flags' => { 'dry_run' => 1 },
    };
}

1;
