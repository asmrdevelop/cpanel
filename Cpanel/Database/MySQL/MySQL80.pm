package Cpanel::Database::MySQL::MySQL80;

# cpanel - Cpanel/Database/MySQL/MySQL80.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::Database::MySQL';

use constant {
    supported           => 1,
    recommended_version => 1,
    short_version       => '80',
    item_short_version  => '8.0',
    selected_version    => 'MySQL80',
    locale_version      => 'MySQL 8.0',
    eol_time            => {
        start => 1524114000,
        end   => 1775019600
    },
    release_notes => 'https://go.cpanel.net/changes-mysql80',
    features      => [
        'Roles exist now for easier user management.',
        'Support for [asis,MySQL Server Components].',
        'Spatial Data support.',
    ],
    auth_field               => 'authentication_string',
    general_upgrade_warnings => [],
    config_upgrade_warnings  => [
        {
            config  => { key => 'sql_mode', value => qr/no_auto_create_user/i, },
            warning => {
                severity => 'Fatal',
                message  => 'The setting "NO_AUTO_CREATE_USER" is not compatible with MySQL® 8. You must remove it from the "sql_mode" variable in the "/etc/my.cnf" file.',
            }
        },
    ],
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

sub validate_config_options ( $self, $cnf ) {
    return [ "--defaults-file=$cnf", '--validate-config' ];
}

sub get_remove_users_sql ( $self, $user_arrayref ) {
    return 0 unless scalar( $user_arrayref->@* );

    my $users = join( ", ", map { $self->_get_quoted_user( 'user' => $_->{'user'}, 'host' => $_->{'host'} ) } $user_arrayref->@* );
    return qq{DROP USER IF EXISTS $users;};
}

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    my @warnings = ();
    return @warnings;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MySQL::MySQL80

=head1 SYNOPSIS

The database module for MySQL 8.0

=head1 DESCRIPTION

This module contains all code and attributes unqiue to MySQL 8.0

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

=head1 METHODS

=over

=item * new -- Returns a blessed object.

=item * set_user_resource_limits -- Updates user resource limits via ALTER USER.

=item * validate_config_options -- Returns the options required to pass to mysqld to validate my.cnf

=back
