package Whostmgr::Transfers::Session::Items::Schema::EximRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/Schema/EximRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0';

sub schema {
    my ($self) = @_;

    return {
        'primary'  => ['name'],
        'required' => ['name'],
        'keys'     => {
            'name'         => { 'def' => 'char(255) DEFAULT NULL' },
            'size'         => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },    # size the the relative timeunits this takes
            'disable_rbls' => { 'def' => 'BIGINT UNSIGNED DEFAULT 0' },
        }
    };
}

1;
