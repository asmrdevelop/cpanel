package Cpanel::Postgres::Connect;

# cpanel - Cpanel/Postgres/Connect.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DBI::Postgresql       ();
use Cpanel::IP::Loopback          ();
use Cpanel::PostgresUtils         ();
use Cpanel::PostgresUtils::PgPass ();

#PgSQL docs recommend using "postgres" as a default login DB.
my $DEFAULT_LOGIN_DATABASE = 'postgres';

#----------------------------------------------------------------------
#Use this function to connect to the system PostgreSQL. It’s most useful
#for connecting as root but accepts arguments to connect to an arbitrary
#PostgreSQL server.
#
#named parameters (NOTE: these all copy DBI’s interface):
#
#   db      - defaults to $DEFAULT_LOGIN_DATABASE, above
#
#   host    - defaults to the return value of Cpanel::PostgresUtils::get_socket_directory(); can also be an IP
#
#   Username  - defaults to system PostgreSQL user (i.e., superuser)
#
#   Password  - defaults to $dbuser’s password
#
sub get_dbi_handle {
    my (%opts) = @_;

    my $pguser = $opts{'Username'} || Cpanel::PostgresUtils::PgPass::getpostgresuser();
    die "Failed to determine PostgreSQL user!" if !$pguser;

    my $pgpass = $opts{'Password'};
    if ( !defined $pgpass ) {
        $pgpass = Cpanel::PostgresUtils::PgPass::pgpass();
        $pgpass &&= $pgpass->{$pguser}{'password'};
    }

    die "Failed to retrieve PostgreSQL password!" if !defined $pgpass;

    my $db = length( $opts{'db'} ) ? $opts{'db'} : $DEFAULT_LOGIN_DATABASE;

    my $host = length( $opts{'host'} ) ? $opts{'host'} : 'localhost';

    my $socket_file = Cpanel::PostgresUtils::get_socket_file();

    my $use_socket       = -S $socket_file;
    my $host_is_loopback = Cpanel::IP::Loopback::is_loopback($host);

    my $use_host;
    if ($host_is_loopback) {

        # DBD::Pg expects 'host' to be the directory that the socket file is in
        $use_host = Cpanel::PostgresUtils::get_socket_directory() if $use_socket;
    }
    else {
        $use_host = $host;
    }

    return Cpanel::DBI::Postgresql->connect(
        {
            # fallback to localhost if we cannot determine a better host to use
            $use_host ? ( host => $use_host ) : ( host => 'localhost' ),

            db       => $db,
            Username => $pguser,
            Password => $pgpass,

            RaiseError => 1,
            PrintError => 1,
        }
    );
}

1;
