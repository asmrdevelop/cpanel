package Cpanel::MysqlUtils::Restart;

# cpanel - Cpanel/MysqlUtils/Restart.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub restart {
    return _system('/usr/local/cpanel/scripts/restartsrv_mysql');    #fork and close is already done
}

sub _system {
    my (@cmd) = @_;
    return system(@cmd);
}

1;
