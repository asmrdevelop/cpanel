package Cpanel::DBI::Postgresql::Utils;

# cpanel - Cpanel/DBI/Postgresql/Utils.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#----------------------------------------------------------------------
#This is a mix-in class that includes common tasks to do with a DBI handle.
#----------------------------------------------------------------------

sub db_exists {
    my ( $self, $dbname ) = @_;

    return $self->selectrow_array( 'SELECT datname FROM pg_database WHERE datname=?', undef, $dbname ) ? 1 : 0;
}

sub role_exists {
    my ( $self, $role_name ) = @_;

    return $self->selectrow_array( 'SELECT rolname FROM pg_roles WHERE rolname=?', undef, $role_name ) ? 1 : 0;
}

sub set_password {
    my ( $self, $role_name, $password ) = @_;

    my $role_q = $self->quote_identifier($role_name);

    return $self->do( "ALTER ROLE $role_q WITH LOGIN PASSWORD ?", undef, $password );
}

#for overriding in testing
sub _get_server_version {
    my ($self) = @_;

    return $self->{'pg_server_version'};
}

sub purge_connections_to_db {
    my ( $self, $dbname ) = @_;

    my $pg_server_version = $self->_get_server_version();

    my $function_name = ( $pg_server_version >= 80400 ) ? 'pg_terminate_backend' : 'pg_cancel_backend';
    my $column_name   = ( $pg_server_version < 90200 )  ? 'procpid'              : 'pid';

    # The process this command gets from pg_stat_activity
    # will sometimes be complete by the time it goes to kill it and cause a warning
    local $self->{'PrintWarn'} = 0;

    return $self->do(
        qq{
            SELECT
                $function_name(pg_stat_activity.$column_name)
            FROM
                pg_stat_activity
            WHERE
                pg_stat_activity.datname = ?
        },
        undef,
        $dbname,
    );
}

1;
