package Cpanel::Validate::DB::Owner;

# cpanel - Cpanel/Validate/DB/Owner.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::DB::Map::Reader::Exists ();
use Cpanel::Validate::DB::User      ();
use Cpanel::Exception               ();
use Cpanel::ConfigFiles             ();

#This function verifies that:
#   - $dbowner is a validly formatted dbowner name
#   - there isn't a dbowner with the same name already on the system.
#
#If PostgreSQL is installed, it verifies the same conditions
#with PostgreSQL in addition to MySQL.
#
#This does not tolerate failure.
#
sub is_valid_dbowner {
    my ($dbowner) = @_;

    my $error_trap;
    try {
        Cpanel::Validate::DB::User::verify_mysql_dbuser_name($dbowner);
    }
    catch {
        $error_trap = $_;
    };

    return ( 0, Cpanel::Exception::get_string($error_trap) ) if $error_trap;

    #TODO: Why is this special for dbowners?
    if ( $dbowner =~ /\A\d+/ ) {
        return ( 0, "The database owner name “$dbowner” is invalid." );
    }

    # Don't need to catch here at the moment as verify_mysql_dbuser_name already performed the
    # verify_mysql_dbuser_name_format check.
    # NOTE: It appears that this logic is confused: the DB map stores by the
    # cpuser name, not by dbowner.
    if ( Cpanel::DB::Map::Reader::Exists::cpuser_exists($dbowner) ) {
        return ( 0, "A database owner with the name “$dbowner” already exists in the database map ($Cpanel::ConfigFiles::DATABASES_INFO_DIR/$dbowner.*)." );
    }

    require Cpanel::PostgresAdmin::Check;
    my $psql_check = Cpanel::PostgresAdmin::Check::is_configured();
    if ( $psql_check && $psql_check->{'status'} ) {
        try {
            Cpanel::Validate::DB::User::verify_pgsql_dbuser_name($dbowner);
        }
        catch {
            $error_trap = $_;
        };

        return ( 0, Cpanel::Exception::get_string($error_trap) ) if $error_trap;
    }

    return 1;
}

1;
