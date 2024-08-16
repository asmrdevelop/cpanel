package Whostmgr::Transfers::Session::Items::Schema::KeyValueBase;

# cpanel - Whostmgr/Transfers/Session/Items/Schema/KeyValueBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Items::Schema::KeyValueBase

=head1 DESCRIPTION

A base class for subclasses of
L<Whostmgr::Transfers::Session::Items::ConfigBackupBase> that all share
a particular identical C<schema()> definition.

=cut

use constant schema => {
    'primary'  => ['name'],
    'required' => ['name'],
    'keys'     => {
        'name' => { 'def' => 'char(255) DEFAULT NULL' },
        'size' => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },    # size the relative timeunits this takes
    },
};

1;
