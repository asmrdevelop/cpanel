package Whostmgr::Transfers::Session::Items::Schema::MailboxConversion;

# cpanel - Whostmgr/Transfers/Session/Items/Schema/MailboxConversion.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.0';

sub schema {
    return {
        'primary'  => ['user'],    # User
        'required' => ['user'],
        'keys'     => {
            'user'          => { 'def' => 'char(255) DEFAULT NULL' },      #  User
            'size'          => { 'def' => 'BIGINT UNSIGNED DEFAULT 1' },
            'target_format' => { 'def' => 'char(255) DEFAULT NULL' },
            'source_format' => { 'def' => 'char(255) DEFAULT NULL' },
            'skip_removal'  => { 'def' => 'INT(1) DEFAULT 0' },
        }
    };
}
1;
