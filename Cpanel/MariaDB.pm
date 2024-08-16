package Cpanel::MariaDB;

# cpanel - Cpanel/MariaDB.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::LoadModule ();

sub version_is_mariadb ($version) {

    return 0 unless defined $version && length $version;

    if ( $version =~ m{^(\d+\.\d+)\D*} ) {
        return ( $1 >= 10.0 ? 1 : 0 );
    }

    return 0 unless $version =~ qr{^[0-9]+$};

    return ( $version >= 100 ? 1 : 0 );
}

sub dbh_is_mariadb ($dbh) {
    return 0 unless defined $dbh;
    return 0 unless ref($dbh) =~ /DBI/ && $dbh->can('selectrow_array');

    my ($version_string) = $dbh->selectrow_array('SELECT VERSION()');
    return ( $version_string =~ /mariadb/i ) ? 1 : 0;
}

sub running_version_is_mariadb {

    Cpanel::LoadModule::load_perl_module('Cpanel::Database');
    my ( $vendor, $version ) = Cpanel::Database::get_vendor_and_version();

    return 1 if $vendor =~ /mariadb/i;
    return 0;
}
1;
