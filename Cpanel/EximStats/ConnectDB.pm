package Cpanel::EximStats::ConnectDB;

# cpanel - Cpanel/EximStats/ConnectDB.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::EximStats::DB::Sqlite ();

sub dbconnect {
    return Cpanel::EximStats::DB::Sqlite->dbconnect();
}

sub dbconnect_no_rebuild {
    return Cpanel::EximStats::DB::Sqlite->dbconnect_no_rebuild();
}

1;
