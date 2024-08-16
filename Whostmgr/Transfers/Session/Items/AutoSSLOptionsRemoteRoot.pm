package Whostmgr::Transfers::Session::Items::AutoSSLOptionsRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/AutoSSLOptionsRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Items::AutoSSLOptionsRemoteRoot

=head1 DESCRIPTION

This module describes to the transfer system how to store
backup data for AutoSSL options configuration.

=cut

use parent (
    'Whostmgr::Transfers::Session::Items::ConfigBackupBase',
    'Whostmgr::Transfers::Session::Items::Schema::AutoSSLOptionsRemoteRoot',
);

use constant module_info => {
    'item_name'            => 'AutoSSLOptions',
    'config_module'        => 'cpanel::system::autossloptions',
    'config_restore_flags' => { 'dry_run' => 1 },
};

1;
