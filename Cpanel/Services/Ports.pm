package Cpanel::Services::Ports;

# cpanel - Cpanel/Services/Ports.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our %SERVICE = (
    'cphttpd'  => 80,
    'cphttpds' => 443,

    'whostmgr'  => 2086,
    'whostmgrs' => 2087,
    'cpanel'    => 2082,
    'cpanels'   => 2083,
    'webmail'   => 2095,
    'webmails'  => 2096,
);

our %PORTS = ( reverse %SERVICE );

1;
