package Whostmgr::Transfers::Session::Items::Schema::AccountBase;

# cpanel - Whostmgr/Transfers/Session/Items/Schema/AccountBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Transfers::Utils::LinkedNodes ();

our $VERSION = '1.0';

sub schema {
    return {
        'primary'      => ['user'],                  # Remote User
        'required'     => [ 'user', 'localuser' ],
        'prerequisite' => 'prerequisite_user',
        'keys'         => {
            'user'                        => { 'def' => 'char(255) DEFAULT NULL' },      # Remote User
            'size'                        => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },
            'files'                       => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },
            'priority'                    => { 'def' => 'int(1) DEFAULT 255' },
            'localuser'                   => { 'def' => 'char(255) DEFAULT NULL' },
            'detected_remote_user'        => { 'def' => 'char(255) DEFAULT NULL' },
            'domain'                      => { 'def' => 'char(255) DEFAULT NULL' },
            'customip'                    => { 'def' => 'char(255) DEFAULT NULL' },
            'replaceip'                   => { 'def' => 'char(255) DEFAULT NULL' },
            'prerequisite_user'           => { 'def' => 'char(255) DEFAULT NULL' },
            'reseller'                    => { 'def' => 'int(1) DEFAULT 0' },
            'force'                       => { 'def' => 'int(1) DEFAULT 0' },
            'ip'                          => { 'def' => 'int(1) DEFAULT 0' },
            'skiphomedir'                 => { 'def' => 'int(1) DEFAULT 0' },
            'shared_mysql_server'         => { 'def' => 'int(1) DEFAULT 0' },
            'skipres'                     => { 'def' => 'int(1) DEFAULT 0' },
            'skipacctdb'                  => { 'def' => 'int(1) DEFAULT 0' },
            'skipbwdata'                  => { 'def' => 'int(1) DEFAULT 0' },
            'skipaccount'                 => { 'def' => 'int(1) DEFAULT 0' },
            'skipsubdomains'              => { 'def' => 'int(1) DEFAULT 0' },
            'skipemail'                   => { 'def' => 'int(1) DEFAULT 0' },
            'overwrite_all_dbs'           => { 'def' => 'int(1) DEFAULT 0' },
            'overwrite_all_dbusers'       => { 'def' => 'int(1) DEFAULT 0' },
            'overwrite_sameowner_dbs'     => { 'def' => 'int(1) DEFAULT 0' },
            'overwrite_sameowner_dbusers' => { 'def' => 'int(1) DEFAULT 0' },
            'xferpoint'                   => { 'def' => 'int(1) DEFAULT 0' },
            'copypoint'                   => { 'def' => 'text' },
            'cpmovefile'                  => { 'def' => 'text' },
            'disabled'                    => { 'def' => 'text' },
            'overwrite_with_delete'       => { 'def' => 'int(1) DEFAULT 0' },
            'live_transfer'               => { 'def' => 'int(1) DEFAULT 0' },
            'keep_local_cpuser_values'    => { 'def' => 'text' },
            (
                map {
                    $_ => { 'def' => 'char(255) DEFAULT NULL' },
                } values %Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER
            ),
        }
    };
}
1;
