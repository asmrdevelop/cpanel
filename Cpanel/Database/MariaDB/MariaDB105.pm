package Cpanel::Database::MariaDB::MariaDB105;

# cpanel - Cpanel/Database/MariaDB/MariaDB105.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::Database::MariaDB';

use constant {
    supported           => 1,
    recommended_version => 0,
    short_version       => '105',
    item_short_version  => '10.5',
    selected_version    => 'MariaDB105',
    locale_version      => 'MariaDB 10.5',
    eol_time            => {
        start => 1592956800,
        end   => 1750723200,
    },
    release_notes => 'https://go.cpanel.net/more-info-maria105',
    features      => [
        'Renamed `mysql` command names to `mariadb` command names, with symlinks put in place in order to maintain backward compatibility.',
        'Several protocol improvements including adding support for the new Data Type API for the JSON and GEOMETRY data types.',
        'The InnoDB storage engine includes substantial changes that improve performance, manageability, and scalability.',
        'More granular privileges, and other security improvements.',
    ],
    fetch_temp_users_key_field => 'User',
    daemon_name                => 'mariadbd',
    general_upgrade_warnings   => [
        {
            'severity' => 'Normal',
            'message'  =>
              'All binaries previously beginning with `mysql` now begin with `mariadb`. Symlinks are created for the corresponding mysql commands to ensure backwards compatibility. Usually that should not cause any changed behavior, but when starting the MariaDB server via systemd, or via the `mysqld_safe` script symlink, the server process will now always be started as `mariadbd`, <b>not</b> `mysqld`. Any 3rd party software or scripts looking for the `mysqld` name in the system process list <b>must</b> now look for `mariadbd` instead.'
        },
        {
            'severity' => 'Critical',
            'message'  => 'In MariaDB 10.4 and later, the mysql.global_priv table has replaced the mysql.user table. The mysql.user table is converted into a view of the mysql.global_priv table during the database upgrade. The dedicated mariadb.sys user is created as the definer of the new mysql.user view.'
        },
        {
            'severity' => 'Critical',
            'message'  => 'The "mytop" package is not compatible due to MDEV-22552. If "mytop" is installed, the upgrade process will uninstall the "mytop" package.'
        },
    ],
    config_upgrade_warnings => [],
};

sub get_set_user_resource_limits_sql ( $self, %opts ) {
    my $user = $self->_get_quoted_user( 'user' => $opts{'user'}, 'host' => $opts{'host'} );
    my $sql  = "ALTER USER $user WITH ";

    # Handle renames, preferring the updated name where applicable.
    my $max_updates_per_hour     = $opts{'max_updates_per_hour'}     //= $opts{'max_updates'};
    my $max_connections_per_hour = $opts{'max_connections_per_hour'} //= $opts{'max_connections'};
    my $max_queries_per_hour     = $opts{'max_queries_per_hour'}     //= $opts{'max_questions'};

    my @limits;
    push( @limits, "MAX_USER_CONNECTIONS $opts{'max_user_connections'}" ) if $opts{'max_user_connections'};
    push( @limits, "MAX_UPDATES_PER_HOUR $max_updates_per_hour" )         if $max_updates_per_hour;
    push( @limits, "MAX_CONNECTIONS_PER_HOUR $max_connections_per_hour" ) if $max_connections_per_hour;
    push( @limits, "MAX_QUERIES_PER_HOUR $max_queries_per_hour" )         if $max_queries_per_hour;
    $sql .= join( ' ', @limits ) . ';';

    return $sql;
}

sub remove_user_from_global_priv ( $self, %opts ) {
    return $self->remove_user_from_generic_priv( %opts, 'table' => 'global_priv' );
}

sub get_remove_users_sql ( $self, $user_arrayref ) {
    return 0 unless scalar( $user_arrayref->@* );

    my $users = join( ", ", map { $self->_get_quoted_user( 'user' => $_->{'user'}, 'host' => $_->{'host'} ) } $user_arrayref->@* );
    return qq{DROP USER IF EXISTS $users;};
}

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    return ();
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MariaDB::MariaDB105

=head1 SYNOPSIS

The database module for MariaDB 10.5

=head1 DESCRIPTION

This module contains all code and attributes unqiue to MariaDB 10.5

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

