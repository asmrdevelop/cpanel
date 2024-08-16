package Cpanel::Database::MySQL::MySQL57;

# cpanel - Cpanel/Database/MySQL/MySQL57.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Database ();

use parent 'Cpanel::Database::MySQL';

use constant {
    supported           => 1,
    recommended_version => 0,
    short_version       => '57',
    item_short_version  => '5.7',
    selected_version    => 'MySQL57',
    locale_version      => 'MySQL 5.7',
    eol_time            => {
        start => 1445385600,
        end   => 1697864400
    },
    is_eol        => 1,
    release_notes => 'https://go.cpanel.net/changes-mysql57',
    features      => [
        'Many [asis,InnoDB] improvements.',
        'Improvements to [asis,PERFORMANCE_SCHEMA].',
        'Several replication improvements.',
        'Improvements to the query optimizer.',
    ],
    auth_field               => 'authentication_string',
    default_sql_mode         => 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION',
    general_upgrade_warnings => [],
    config_upgrade_warnings  => [],
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

sub get_root_pw_init_file_sql ( $self, $quoted_password ) {

    require Cpanel::MysqlUtils::Reset;
    require Cpanel::MysqlUtils::Quote;

    my @sql = ();

    for my $localhost ( Cpanel::Database::_localhosts_for_root_user() ) {
        my $fullname = $self->_get_quoted_user( 'user' => 'root', 'host' => $localhost );

        push @sql, "SET GLOBAL old_passwords=0;";
        push @sql, $self->get_set_password_sql( name => $fullname, pass => $quoted_password, plugin => 'mysql_native_password', exists => 1, hashed => 0 );
        push @sql, $self->get_password_lifetime_sql( quoted_user => Cpanel::MysqlUtils::Quote::quote('root'), quoted_host => Cpanel::MysqlUtils::Quote::quote($localhost) );
        push @sql, $self->get_password_unexpire_sql( quoted_user => Cpanel::MysqlUtils::Quote::quote('root'), quoted_host => Cpanel::MysqlUtils::Quote::quote($localhost) );
        push @sql, $self->get_set_user_resource_limits_sql(
            'user'                 => 'root',
            'host'                 => $localhost,
            'max_user_connections' => $Cpanel::MysqlUtils::Reset::MAX_SIGNED_INT,
            'max_updates'          => $Cpanel::MysqlUtils::Reset::MAX_SIGNED_INT,
            'max_connections'      => $Cpanel::MysqlUtils::Reset::MAX_SIGNED_INT,
            'max_questions'        => $Cpanel::MysqlUtils::Reset::MAX_SIGNED_INT,
        );
        push @sql, "SET GLOBAL innodb_max_dirty_pages_pct=0;";
    }

    return \@sql;
}

sub get_remove_users_sql ( $self, $user_arrayref ) {
    return 0 unless scalar( $user_arrayref->@* );

    my $users = join( ", ", map { $self->_get_quoted_user( 'user' => $_->{'user'}, 'host' => $_->{'host'} ) } $user_arrayref->@* );
    return qq{DROP USER IF EXISTS $users;};
}

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    my @warnings = ();

    my $installed_version = $opts{'from_version'};
    my $target_version    = $self->item_short_version;

    if ( $installed_version < $target_version ) {
        push @warnings, {
            'severity' => 'Critical',
            'message'  =>
              'MySQL enables "strict mode" by default as of version 5.7. Strict mode controls how MySQL handles invalid or missing values in data-change statements such as INSERT or UPDATE. Applications not built with strict mode enabled may cause undesired behavior; please verify applications using MySQL are compatible before upgrading. More information about strict mode is available <a target="_blank" href="https://go.cpanel.net/sqlmodestrict">here</a> <i class="fas fa-external-link-alt" aria-hidden="true"></i>.'
        };

        local $SIG{__DIE__};
        my ( $has_sys_database, $error ) = $self->_db_exists('sys');

        if ($has_sys_database) {
            push @warnings, {
                'severity' => 'Fatal',
                'message'  => 'MySQL 5.7 includes a new database named "sys". A database with this name already exists. Remove or rename this database before continuing.'
            };
        }
        elsif ( $error || !defined($has_sys_database) ) {
            push @warnings, {
                'severity' => 'Critical',
                'message'  => "The update could not reach the MySQL server to check for the existence of a database named 'sys'. This issue could also hinder mysql_upgrade's ability to run, which could potentially leave MySQL in an unusable state if you proceed.\n",
            };
        }
    }

    return @warnings;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MySQL::MySQL57

=head1 SYNOPSIS

The database module for MySQL 5.7

=head1 DESCRIPTION

This module contains all code and attributes unqiue to MySQL 5.7

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

=head1 METHODS

=over

=item * new -- Returns a blessed object.

=item * set_user_resource_limits -- Updates user resource limits via ALTER USER.

=back
