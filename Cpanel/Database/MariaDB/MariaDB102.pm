package Cpanel::Database::MariaDB::MariaDB102;

# cpanel - Cpanel/Database/MariaDB/MariaDB102.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::Database::MariaDB';

use constant {
    supported           => 1,
    recommended_version => 0,
    short_version       => '102',
    item_short_version  => '10.2',
    selected_version    => 'MariaDB102',
    locale_version      => 'MariaDB 10.2',
    eol_time            => {
        start => 1495497600,
        end   => 1653264000
    },
    release_notes => 'https://go.cpanel.net/changelog-mariadb102',
    features      => [
        'Improved connection performance.',
    ],
    populate_password_column => 1,
    general_upgrade_warnings => [
        {
            'severity' => 'Critical',
            'message'  =>
              'MariaDB enables "strict mode" by default as of version 10.2. Strict mode controls how MariaDB and MySQL handle invalid or missing values in data-change statements such as INSERT or UPDATE. Applications not built with strict mode enabled may cause undesired behavior; please verify applications using MariaDB are compatible before upgrading. More information about strict mode is available <a target="_blank" href="https://go.cpanel.net/sqlmodestrict">here</a> <i class="fas fa-external-link-alt" aria-hidden="true"></i>.'
        },
    ],
    config_upgrade_warnings => [],
    is_eol                  => 1,
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

sub get_enable_default_auth_plugin_sql ( $self, %opts ) {

    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host}   ? qq{ AND Host = $quoted_host_or_bind} : q{};
    my $nice_plugin_change  = $opts{force_plugin} ? ''                                   : " AND (plugin = '' OR plugin = null OR plugin = 'mysql_old_password' OR plugin = 'auth_socket')";
    my $plugin              = $self->default_plugin;

    return qq{UPDATE mysql.user SET plugin = '$plugin' WHERE User = $quoted_user_or_bind$host_string$nice_plugin_change};
}

sub get_password_lifetime_sql ( $self, @ ) {
    return qq{};    # Not supported
}

sub get_password_unexpire_sql ( $self, %opts ) {
    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host} ? qq{ AND Host = $quoted_host_or_bind} : q{};

    return qq{UPDATE mysql.user SET password_expired='N' WHERE User = $quoted_user_or_bind$host_string};
}

sub get_remove_users_sql ( $self, $user_arrayref ) {
    return 0 unless scalar( $user_arrayref->@* );

    my $users = join( ", ", map { $self->_get_quoted_user( 'user' => $_->{'user'}, 'host' => $_->{'host'} ) } $user_arrayref->@* );
    return qq{DROP USER IF EXISTS $users;};
}

sub remove_user_from_global_priv ( $self, %opts ) {
    return $self->remove_user_from_generic_priv( %opts, 'table' => 'user' );
}

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    return ();
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MariaDB::MariaDB102

=head1 SYNOPSIS

The database module for MariaDB 10.2

=head1 DESCRIPTION

This module contains all code and attributes unique to MariaDB 10.2

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

=head1 METHODS

=over

=item * new -- Returns a blessed object.

=item * set_user_resource_limits -- Updates user resource limits via ALTER USER.

=back
