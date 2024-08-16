package Whostmgr::Transfers::Session::Items::Schema::PackageRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/Schema/PackageRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.1';

sub schema {
    my ($self) = @_;

    return {
        'primary'  => ['package'],
        'required' => ['package'],
        'keys'     => {

            # Trailing spaces :( are allowed in package names
            # so we need varchar
            'package' => { 'def' => 'varchar(255) DEFAULT NULL' },
            'size'    => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },
        }
    };
}

1;
