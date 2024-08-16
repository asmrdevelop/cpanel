package Cpanel::Database::MariaDB::MariaDB100;

# cpanel - Cpanel/Database/MariaDB/MariaDB100.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::Database::MariaDB';

use constant {
    supported           => 1,
    recommended_version => 0,
    short_version       => '100',
    item_short_version  => '10.0',
    selected_version    => 'MariaDB100',
    locale_version      => 'MariaDB 10.0',
    eol_time            => {
        start => 1396220400,
        end   => 1553990400
    },
    release_notes => 'https://go.cpanel.net/changelog-mariadb100',
    features      => [
        'Improved performance and speed.',
        'New query optimizer.',
        'Faster joins.',
        'More storage engines.',
        '[asis,PAM] support.',
    ],
    default_sql_mode         => "''",
    populate_password_column => 1,
    general_upgrade_warnings => [],
    config_upgrade_warnings  => [],
    is_eol                   => 1,
};

sub get_set_password_sql ( $self, %opts ) {

    my @missing_args = grep { !exists $opts{$_} } (qw/ name pass exists hashed plugin /);
    die "Missing needed arguments: " . join( ",", @missing_args ) if @missing_args;

    my $has_pass = ( $opts{pass} && $opts{pass} ne 'NULL' );

    my $sql;
    if ( $opts{exists} ) {
        $sql .= "SET PASSWORD FOR $opts{name} = ";
        $sql .= $opts{hashed} ? "$opts{pass};" : "PASSWORD($opts{pass});";
    }
    else {
        $sql .= "CREATE USER $opts{name}";

        if ($has_pass) {

            $sql .= " IDENTIFIED BY ";
            $sql .= $opts{hashed} ? 'PASSWORD ' : '';
            $sql .= "$opts{pass};";

        }
        else {
            $sql .= ';';
        }
    }

    $sql .= " $opts{method} USAGE ON *.* TO $opts{name};" if $opts{method};

    # See t/Cpanel-Mysql-Create.t test___user_and_grant_management_cb() to see what this sql is expected to look like.
    return $sql;
}

sub get_enable_default_auth_plugin_sql ( $self, %opts ) {

    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host}   ? qq{ AND Host = $quoted_host_or_bind} : q{};
    my $nice_plugin_change  = $opts{force_plugin} ? ''                                   : " AND (plugin = '' OR plugin = null OR plugin = 'mysql_old_password' OR plugin = 'auth_socket')";
    my $plugin              = $self->default_plugin;

    return qq{UPDATE mysql.user SET plugin = '$plugin' WHERE User = $quoted_user_or_bind$host_string$nice_plugin_change;};
}

sub get_password_lifetime_sql ( $self, @ ) {
    return qq{};    # Not supported
}

sub get_password_unexpire_sql ( $self, %opts ) {
    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host} ? qq{ AND Host = $quoted_host_or_bind} : q{};

    return qq{UPDATE mysql.user SET password_expired='N' WHERE User = $quoted_user_or_bind$host_string;};
}

sub get_set_user_resource_limits_sql ( $self, %opts ) {
    my $sql = "UPDATE mysql.user SET ";

    my @limits;
    push( @limits, "MAX_USER_CONNECTIONS=$opts{'max_user_connections'}" ) if $opts{'max_user_connections'};
    push( @limits, "MAX_UPDATES=$opts{'max_updates'}" )                   if $opts{'max_updates'};
    push( @limits, "MAX_CONNECTIONS=$opts{'max_connections'}" )           if $opts{'max_connections'};
    push( @limits, "MAX_QUESTIONS=$opts{'max_questions'}" )               if $opts{'max_questions'};
    $sql .= join( ', ', @limits ) . " WHERE User='$opts{'user'}'";
    $sql .= $opts{'host'} ? " AND Host='$opts{'host'}';" : ';';

    return $sql;
}

sub get_remove_users_sql ( $self, $user_arrayref ) {
    return 0 unless scalar( $user_arrayref->@* );

    my $users = join( ", ", map { $self->_get_quoted_user( 'user' => $_->{'user'}, 'host' => $_->{'host'} ) } $user_arrayref->@* );
    return qq{DROP USER $users;};
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

Cpanel::Database::MariaDB::MariaDB100

=head1 SYNOPSIS

The database module for MariaDB 10.0

=head1 DESCRIPTION

This module contains all code and attributes unique to MariaDB 10.0

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

=head1 METHODS

=over

=item * new -- Returns a blessed object.

=item * get_set_password_sql -- Returns the sql statement to set the password for a user.

=back
