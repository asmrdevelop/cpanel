package Cpanel::DbUtils;

# cpanel - Cpanel/DbUtils.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::FindBin ();

our $VERSION = 1.2;

sub _find_bin {
    return Cpanel::FindBin::findbin( $_[0], ( defined $_[1] ? $_[1] : () ) );
}

#mysql client
sub find_mysql        { return _find_bin('mysql'); }
sub find_mysql_config { return _find_bin('mysql_config'); }
sub find_mysqladmin   { return _find_bin('mysqladmin'); }
sub find_mysqlcheck   { return _find_bin('mysqlcheck'); }
sub find_mysqldump    { return _find_bin('mysqldump'); }

# mysql server
sub find_mysql_fix_privilege_tables { return _find_bin('mysql_fix_privilege_tables'); }
sub find_mysql_upgrade              { return _find_bin('mysql_upgrade') }
sub find_mysql_install_db           { return _find_bin('mysql_install_db') }
sub find_mysqld                     { return _find_bin( 'mysqld', [ '/usr/bin', '/usr/sbin', '/usr/local/bin', '/usr/local/sbin', '/usr/libexec', '/usr/local/libexec' ] ); }

# psql client
sub find_pg_dump    { return _find_bin('pg_dump') }
sub find_pg_restore { return _find_bin('pg_restore') }
sub find_psql       { return _find_bin('psql') }

# psql Server
sub find_postmaster { return _find_bin('postmaster') }
sub find_createdb   { return _find_bin('createdb'); }
sub find_pg_ctl     { return _find_bin('pg_ctl'); }
sub find_createuser { return _find_bin('createuser'); }
sub find_dropdb     { return _find_bin('dropdb'); }
sub find_dropuser   { return _find_bin('dropuser'); }

1;
