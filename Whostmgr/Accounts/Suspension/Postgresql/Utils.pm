package Whostmgr::Accounts::Suspension::Postgresql::Utils;

# cpanel - Whostmgr/Accounts/Suspension/Postgresql/Utils.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#TODO: Does this module need to do anything to prevent triggers, events, etc.
#from running while a PostgreSQL account is suspended?

use strict;

our $SUSPEND_SUFFIX = '-cpsuspend';

1;
