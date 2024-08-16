package Whostmgr::Transfers::Session::Items::Schema::LegacyAccountBackup;

# cpanel - Whostmgr/Transfers/Session/Items/Schema/LegacyAccountBackup.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.0';

sub schema {
    return {
        'primary'  => ['user'],                    # Remote User
        'required' => [ 'user', 'restoretype' ],
        'keys'     => {
            'user'                        => { 'def' => 'char(255) DEFAULT NULL' },      # Remote User
            'size'                        => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },
            'files'                       => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },
            'restoretype'                 => { 'def' => 'char(255) DEFAULT NULL' },
            'restoreall'                  => { 'def' => 'int(1) DEFAULT 0' },
            'restoreip'                   => { 'def' => 'int(1) DEFAULT 0' },
            'restoremail'                 => { 'def' => 'int(1) DEFAULT 0' },
            'restoremysql'                => { 'def' => 'int(1) DEFAULT 0' },
            'restorepsql'                 => { 'def' => 'int(1) DEFAULT 0' },
            'restorebwdata'               => { 'def' => 'int(1) DEFAULT 0' },
            'restoresubs'                 => { 'def' => 'int(1) DEFAULT 0' },
            'unrestricted_restore'        => { 'def' => 'int(1) DEFAULT 0' },
            'overwrite_all_dbs'           => { 'def' => 'int(1) DEFAULT 0' },
            'overwrite_all_dbusers'       => { 'def' => 'int(1) DEFAULT 0' },
            'overwrite_sameowner_dbs'     => { 'def' => 'int(1) DEFAULT 0' },
            'overwrite_sameowner_dbusers' => { 'def' => 'int(1) DEFAULT 0' },
            'mysql_dbs_to_restore'        => { 'def' => 'text' },
            'pgsql_dbs_to_restore'        => { 'def' => 'text' },
        }
    };
}
1;
