package Cpanel::PostgresUtils::DefaultDB;

# cpanel - Cpanel/PostgresUtils/DefaultDB.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::DB::Map::Reader ();

# this can also be improved using a cache
sub get_defaultdb_for_user {
    my ($cpuser) = @_;
    return unless defined $cpuser;

    # problem when creating the map object in cpsrvd
    my $map = Cpanel::DB::Map::Reader->new( 'cpuser' => $cpuser, engine => 'postgresql' );
    my @dbs = sort { length $a <=> length $b } $map->get_databases();

    return $dbs[0];
}

1;
