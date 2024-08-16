package Whostmgr::Transfers::Session::Items::Schema::FeatureListRemoteRoot;

# cpanel - Whostmgr/Transfers/Session/Items/Schema/FeatureListRemoteRoot.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.1';

sub schema {
    return {
        'primary'  => ['featurelist'],
        'required' => ['featurelist'],
        'keys'     => {

            # Trailing spaces :( are allowed in featurelist names so
            # we need varchar
            'featurelist' => { 'def' => 'varchar(255) DEFAULT NULL' },
            'size'        => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },
        }
    };
}
1;
