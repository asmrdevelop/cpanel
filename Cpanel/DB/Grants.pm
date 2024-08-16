package Cpanel::DB::Grants;

# cpanel - Cpanel/DB/Grants.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Create

=head1 SYNOPSIS

    $grants_hr = get_cpuser_mysql_grants( 'cpuser1' );

    $grants_hr = get_cpuser_postgresql_grants( 'cpuser2' );

=head1 FUNCTIONS

=head2 get_cpuser_mysql_grants( $CP_USERNAME )

Returns a hashref of grants for the given cP user and owned DB users.
The hash keys are the DB users (including the cP user’s dbowner), and each
value is a reference to an array of MySQL statements that will recreate
that MySQL user’s grants.

=cut

sub get_cpuser_mysql_grants {
    my ($cpuser) = @_;

    require Cpanel::Mysql::Basic;
    my $cpmysql         = Cpanel::Mysql::Basic->new( { 'cpuser' => $cpuser } );
    my @users_and_hosts = $cpmysql->listusersandhosts();

    my %GRANTS;

    local $@;

    foreach my $array_ref (@users_and_hosts) {
        my $user = $array_ref->[0];
        my $host = $array_ref->[1];
        my @grants;

        if ( eval { @grants = _get_user_host_grants( $cpmysql, $user, $host ); 1 } ) {
            push @{ $GRANTS{$user} }, @grants;
        }
        else {
            warn "Failed to retrieve MySQL/MariaDB grants for '$user'@'$host': $@";
        }
    }

    return \%GRANTS;
}

sub _get_user_host_grants {
    my ( $cpmysql, $user, $host ) = @_;

    # TODO: Get this information without using $cpmysql’s internals.
    return $cpmysql->{'dbh'}->show_grants( $user, $host );
}

#----------------------------------------------------------------------

=head2 get_cpuser_postgresql_grants( $CP_USERNAME )

Like C<get_cpuser_mysql_grants()> but for PostgreSQL.

=cut

sub get_cpuser_postgresql_grants {
    my ($cpuser) = @_;

    require Cpanel::PostgresAdmin::Basic;
    require Cpanel::PostgresUtils::Quote;

    my $pg_admin = Cpanel::PostgresAdmin::Basic->new( { 'cpuser' => $cpuser } );
    my %GRANTS;
    my %USERS = $pg_admin->listuserspasswds();

    foreach my $user ( keys %USERS ) {
        push @{ $GRANTS{$user} }, qq{CREATE USER } . Cpanel::PostgresUtils::Quote::quote_identifier($user) . qq{ WITH PASSWORD } . Cpanel::PostgresUtils::Quote::quote( $USERS{$user} ) . qq{;};
    }

    my %dbusers = $pg_admin->listusersindb();

    foreach my $db ( keys %dbusers ) {
        foreach my $user ( @{ $dbusers{$db} } ) {
            push @{ $GRANTS{$user} }, qq{GRANT ALL ON DATABASE } . Cpanel::PostgresUtils::Quote::quote_identifier($db) . qq{ TO } . Cpanel::PostgresUtils::Quote::quote_identifier($user) . qq{;};
        }
    }

    return \%GRANTS;
}

1;
