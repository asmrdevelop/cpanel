package Cpanel::Config::Constants::MySQL;

# cpanel - Cpanel/Config/Constants/MySQL.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# 3 hours time limit when fetching mysql dump
our $TIMEOUT_MYSQLDUMP = 10800;

# 1 hour time limit for updating privileges, associated with cpses_tool
our $TIMEOUT_UPDATEPRIVS = 3600;

# 1 hour time limit for updating privileges, associated with cpmysql's DBCACHE call
our $TIMEOUT_DBCACHE = 3600;

1;
