package Cpanel::Compat::DBDmysql;

# cpanel - Cpanel/Compat/DBDmysql.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# This module ensures that DBI gets loaded and
# gets re-inited before DBD::mysql is loadded.  You should
# load this module instead of DBD::mysql or DBI directly
# when you need to have the code work with perlcc

# DBD::Sponge is shipped as of v58 or earlier
#
use DBI                         ();    #before DBD::mysql
use DBD::mysql                  ();
use DBD::mysql::GetInfo         ();    # compile in since we do not ship
use Cpanel::MysqlUtils::Connect ();    # PPI USE OK - If we load up DBD mysql, make sure cpanel is using it
1;
