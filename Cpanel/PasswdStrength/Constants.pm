package Cpanel::PasswdStrength::Constants;

# cpanel - Cpanel/PasswdStrength/Constants.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our %APPNAMES = (
    'cpaddons'   => 'Site Software Installs',
    'createacct' => 'Account Creation (New System/cPanel Accounts)',
    'ftp'        => 'FTP Accounts',
    'list'       => 'Mailing Lists',
    'mysql'      => 'MySQL Users',
    'passwd'     => 'System/cPanel Accounts',
    'postgres'   => 'PostgreSQL Users',
    'sshkey'     => 'SSH Keys',
    'virtual'    => 'Email, FTP, and WebDisk/WebDAV Accounts'
);

1;
