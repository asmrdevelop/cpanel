package Whostmgr::Config::Mysql;

# cpanel - Whostmgr/Config/Mysql.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our %files = (
    '/etc/my.cnf'               => { 'special' => "present" },
    '/var/cpanel/cpanel.config' => { 'special' => "cpanel_config" },
);

1;
