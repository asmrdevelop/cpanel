package Cpanel::DB::Map::Utils;

# cpanel - Cpanel/DB/Map/Utils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Config::LoadUserOwners ();
use Cpanel::DB::Map::Reader        ();
use Cpanel::DB::Prefix             ();

my %ENGINE_TRANSLATION = qw(
  MYSQL   mysql
  PGSQL   postgresql
);

#In the absence of an actual "index", we have to do this the hard way:
#
#1) First see if the dbuser name offers any clues. Most of the time,
#   everything before the prefix matches the cpuser's account name.
#
#2) If that fails, query the database for what privileges the dbuser has.
#   There should be at least one other dbuser that has privileges on the
#   DB, and at least one of those would be the cpuser’s dbowner. Open that
#   user’s DB map file, if such a user exists. (NB: This step is implemented
#   only for MySQL right now.)
#
#3) Finally, if all else fails, query each of the cpusers' DB maps until
#we get a match.
#
#Args are:
#   - the "engine" argument, as passed to Cpanel::DB::Map::new()
#   - the DB user's name
#   - OPTIONAL: a DBI handle
#
#The return is either the cpuser name, or undef if it's unowned.
#
#NOTE: This duplicates some of the logic in Cpanel::DB::Map::Collection.
#The duplication was unintentional; however, this implementation will be
#much faster for most servers since almost everyone uses DB prefixing.
#
sub get_cpuser_for_engine_dbuser {
    my ( $engine, $dbuser, $dbi ) = @_;

    my $rdr_engine = $ENGINE_TRANSLATION{$engine};
    die "Invalid engine: “$engine”" if !$rdr_engine;

    #1) Check for a prefix match.
    if ( $dbuser =~ m<\A([^_]+)_> ) {
        my $prefix = $1;
        my $user   = _prefix_to_username($prefix);

        if ($user) {
            my $map = try { Cpanel::DB::Map::Reader->new( engine => $rdr_engine, cpuser => $user ) };
            return $user if $map && $map->dbuser_exists($dbuser);
        }
    }

    #2) Query the database for common ownership.
    if ( $rdr_engine eq 'mysql' ) {
        my $cpuser = _look_for_mysql_owner_via_dbi( $dbuser, $dbi );
        return $cpuser if $cpuser;
    }

    #3) Query all of the cpusers.
    my $userowners_hr  = _load_user_to_owner_hashref();
    my @users_to_check = sort keys %$userowners_hr;

    return _get_cpuser_owner_from_list( $rdr_engine, $dbuser, \@users_to_check );
}

sub _get_cpuser_owner_from_list {
    my ( $rdr_engine, $dbuser, $cpusers_ar ) = @_;

    while (@$cpusers_ar) {
        my $user_to_return;
        try {
            while ( my $user = shift @$cpusers_ar ) {
                my $map = Cpanel::DB::Map::Reader->new( engine => $rdr_engine, cpuser => $user );
                if ( $map->dbuser_exists($dbuser) ) {
                    $user_to_return = $user;
                    last;    ## no critic(ProhibitExitingSubroutine)
                }
            }
        }
        catch {
            die $_ if !try { $_->isa('Cpanel::Exception::Database::CpuserNotInMap') };
        };

        return $user_to_return if defined $user_to_return;
    }

    return undef;
}

sub _look_for_mysql_owner_via_dbi {
    my ( $dbuser, $dbi ) = @_;

    $dbi ||= do {
        require Cpanel::MysqlUtils::Connect;
        Cpanel::MysqlUtils::Connect::get_dbi_handle();
    };

    # If the dbuser has privileges on any databases, we can
    # use that to guess a cpuser. Because the cpuser owner has privileges
    # on all database on which one of their dbusers have privileges,
    # we can use this as a means of idenftifying potential cpusers that
    # own the given DB user.
    #
    # NB: Cpanel::DB::Map::Collection::Index is arguably a cleaner
    # approach to this problem since it doesn’t require DB access.
    #
    my $dbusers_ar = $dbi->selectcol_arrayref(
        q<
            SELECT DISTINCT user
            FROM mysql.db AS db1
            WHERE EXISTS (
                SELECT 1
                FROM mysql.db AS db2

                -- NB: “BINARY” isn’t needed for case-sensitive matching
                -- because mysql.db.db’s collation is utf8_bin.
                -- That’s fortunate because “BINARY”, for some reason,
                -- makes this query take a very long time!
                WHERE db1.db = db2.db
                  AND db2.user = ?
            );
        >,
        undef,
        $dbuser,
    );

    if (@$dbusers_ar) {
        require Cpanel::AcctUtils::Account;

        my @cpusers = grep { Cpanel::AcctUtils::Account::accountexists($_) } @$dbusers_ar;

        if (@cpusers) {
            return _get_cpuser_owner_from_list( 'mysql', $dbuser, \@cpusers );
        }
    }

    return undef;
}

#For testing
sub _prefix_to_username {
    my ($prefix) = @_;

    return Cpanel::DB::Prefix::prefix_to_username($prefix);
}

#For testing
sub _load_user_to_owner_hashref {
    return Cpanel::Config::LoadUserOwners::loadtrueuserowners( undef, 1, 1 );
}

1;
