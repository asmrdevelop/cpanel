package Cpanel::Sys::Uptime;

# cpanel - Cpanel/Sys/Uptime.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Sys::Info ();

sub get_uptime {
    return Cpanel::Sys::Info::sysinfo()->{'uptime'};
}
1;
