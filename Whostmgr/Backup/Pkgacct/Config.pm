package Whostmgr::Backup::Pkgacct::Config;

# cpanel - Whostmgr/Backup/Pkgacct/Config.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $MAX_SESSION_AGE = ( 86400 * 30 );    # 30 days in seconds
our $SESSION_TIMEOUT = ( 86400 * 2 );     #  2 days in seconds
our $READ_TIMEOUT    = ( 60 * 15 );       # 15 minutes

our $SESSION_DIR = '/var/cpanel/pkgacct_sessions';

1;
