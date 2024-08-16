package Whostmgr::Transfers::Session::Items::WHMConfRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/WHMConfRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0';

use parent (
    'Whostmgr::Transfers::Session::Items::ConfigBackupBase',
    'Whostmgr::Transfers::Session::Items::Schema::WHMConfRemoteRoot',
);

sub module_info {
    my ($self) = @_;

    return {
        'item_name'            => 'WHMConf',
        'config_module'        => 'cpanel::system::whmconf',
        'config_restore_flags' => { 'dry_run' => 1 },
    };
}

1;
