package Whostmgr::Transfers::Session::Items::HulkRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/HulkRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Items::HulkRemoteRoot

=head1 DESCRIPTION

This module describes to the transfer system how to store
backup data for Hulk configuration.

=cut

use parent (
    'Whostmgr::Transfers::Session::Items::ConfigBackupBase',
    'Whostmgr::Transfers::Session::Items::Schema::HulkRemoteRoot',
);

use constant module_info => {
    'item_name'            => 'Hulk',
    'config_module'        => 'cpanel::system::hulk',
    'config_restore_flags' => { 'dry_run' => 1 },
};

1;
