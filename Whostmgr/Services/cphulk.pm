package Whostmgr::Services::cphulk;

# cpanel - Whostmgr/Services/cphulk.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hulkd::Daemon ();

*reload_service = *Cpanel::Hulkd::Daemon::reload_daemons;

1;
