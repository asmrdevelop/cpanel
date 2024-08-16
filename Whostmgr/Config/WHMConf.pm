package Whostmgr::Config::WHMConf;

# cpanel - Whostmgr/Config/WHMConf.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our %whm_files = (
    '/var/cpanel/cpanel.config' => { 'special' => 'archive' },
    '/etc/wwwacct.conf'         => { 'special' => 'merge' },
    '/etc/wwwacct.conf.shadow'  => { 'special' => 'present' },
);

1;
