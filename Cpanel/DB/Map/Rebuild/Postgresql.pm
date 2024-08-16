package Cpanel::DB::Map::Rebuild::Postgresql;

# cpanel - Cpanel/DB/Map/Rebuild/Postgresql.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DB::Utils            ();
use Cpanel::LoadModule           ();
use Cpanel::PostgresAdmin::Check ();

#Returns a hashref of:
#{
#   db1 => [],
#   db2 => [ 'dbuser1', .. ],
#}
#
#The hashref does NOT include the dbowner.
#
sub read_dbmap_data {
    my ($username) = @_;

    my %db_dbusers;

    if ( Cpanel::PostgresAdmin::Check::is_enabled_and_configured() ) {

        # load modules explicitely to help PPI parsing
        Cpanel::LoadModule::load_perl_module('Cpanel::Postgres::Connect');
        Cpanel::LoadModule::load_perl_module('Cpanel::PostgresUtils');

        my $dbowner = Cpanel::DB::Utils::username_to_dbowner($username);

        my $dbh = Cpanel::Postgres::Connect::get_dbi_handle();

        #This works because we have always created a role with the same
        #name as a PostgreSQL database.
        my $dbs_ar = $dbh->selectcol_arrayref(
            q<
                SELECT datname
                FROM pg_database, information_schema.applicable_roles
                WHERE grantee = ? AND role_name = datname
            >,
            undef,
            $dbowner,
        );

        for my $dbname (@$dbs_ar) {
            my $grantees_ar = Cpanel::PostgresUtils::get_role_grantees( $dbh, $dbname );
            $_ = $_->{'grantee'} for @$grantees_ar;
            $db_dbusers{$dbname} = [ grep { $_ ne $dbowner } @$grantees_ar ];
        }
    }

    return \%db_dbusers;
}

1;
