package Whostmgr::Accounts::Suspension::Postgresql;

# cpanel - Whostmgr/Accounts/Suspension/Postgresql.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#TODO: Does this module need to do anything to prevent triggers, events, etc.
#from running while a PostgreSQL account is suspended?

use strict;
use warnings;

use Cpanel::Debug ();

use Whostmgr::Accounts::Suspension::Postgresql::Utils ();

use Try::Tiny;

my $SUSPEND_SUFFIX = $Whostmgr::Accounts::Suspension::Postgresql::Utils::SUSPEND_SUFFIX;

sub suspend {
    my ($username) = @_;

    return _alter_postgresql_password_when_needed(
        $username,
        qq<(rolpassword || E'$SUSPEND_SUFFIX')>,
        qq<SUBSTR( rolpassword, 1 + LENGTH(rolpassword) - LENGTH(E'$SUSPEND_SUFFIX') ) != E'$SUSPEND_SUFFIX'>,
    );
}

sub unsuspend {
    my ($username) = @_;

    return _alter_postgresql_password_when_needed(
        $username,
        qq<REPLACE( rolpassword, E'$SUSPEND_SUFFIX', E'' )>,
        qq<SUBSTR( rolpassword, 1 + LENGTH(rolpassword) - LENGTH(E'$SUSPEND_SUFFIX') ) = E'$SUSPEND_SUFFIX'>,
    );
}

sub _alter_postgresql_password_when_needed {
    my ( $username, $rolpassword_sql, $condition_sql ) = @_;

    require Cpanel::DB::Map::Reader;
    require Cpanel::DB::Utils;
    require Cpanel::Postgres::Connect;
    require Cpanel::PostgresUtils::Quote;

    my $dbmap;

    try {
        $dbmap = Cpanel::DB::Map::Reader->new(
            cpuser => $username,
            engine => 'postgresql',
        );

    }
    catch {
        die $_ if !try { $_->isa('Cpanel::Exception::Database::CpuserNotInMap') };
        Cpanel::Debug::log_warn($_);
    };

    return 0 if !$dbmap;    # Warn when the user does not have a dbmap, however do not trigger rollback

    my $dbh = Cpanel::Postgres::Connect::get_dbi_handle();

    my $dbowner = Cpanel::DB::Utils::username_to_dbowner($username);
    my @dbusers = $dbmap->get_dbusers();

    my $users_sql = '(' . join( ',', map { Cpanel::PostgresUtils::Quote::quote($_) } $dbowner, @dbusers ) . ')';

    $dbh->do(
        qq<
        UPDATE pg_authid
        SET rolpassword = $rolpassword_sql
        WHERE rolname in $users_sql AND $condition_sql
    >
    );

    return 1;
}

1;
