package Cpanel::Database::MySQL::MySQL55;

# cpanel - Cpanel/Database/MySQL/MySQL55.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Database ();

use parent 'Cpanel::Database::MySQL';

use constant {
    supported           => 1,
    recommended_version => 0,
    short_version       => '55',
    item_short_version  => '5.5',
    selected_version    => 'MySQL55',
    locale_version      => 'MySQL 5.5',
    eol_time            => {
        start => 1291356000,
        end   => 1543816800
    },
    release_notes => '',
    features      => [
        '[asis,InnoDB] is the default storage engine.',
        'Improved scalability on multi-core [asis,CPU]s.',
        'Enhancements to [asis,XML] functionality.',
        'Semisynchronous replication.',
        'Support for [asis,PERFORMANCE_SCHEMA].',
    ],
    prefix_length            => 8,
    max_dbuser_length        => 16,
    default_sql_mode         => "''",
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

sub get_disable_auth_plugin_sql ( $self, %opts ) {

    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host}   ? qq{ AND Host = $quoted_host_or_bind} : q{};
    my $nice_plugin_change  = $opts{force_plugin} ? ''                                   : " AND (plugin = 'mysql_native_password' OR plugin = 'mysql_old_password' OR plugin = 'auth_socket')";

    return qq{UPDATE mysql.user SET plugin = '' WHERE User = $quoted_user_or_bind$host_string$nice_plugin_change;};
}

sub get_password_lifetime_sql ( $self, @ ) {
    return qq{};    # Not supported
}

sub get_password_unexpire_sql ( $self, @ ) {
    return qq{};    # Not supported
}

sub get_root_pw_init_file_sql ( $self, $quoted_password ) {

    require Cpanel::MysqlUtils::Reset;
    require Cpanel::MysqlUtils::Quote;

    my @sql = ();

    for my $localhost ( Cpanel::Database::_localhosts_for_root_user() ) {
        my $fullname    = $self->_get_quoted_user( 'user' => 'root', 'host' => $localhost );
        my $quoted_user = Cpanel::MysqlUtils::Quote::quote('root');

        push @sql, "SET GLOBAL old_passwords=0;";
        push @sql, $self->get_set_password_sql( name => $fullname, pass => $quoted_password, plugin => 'mysql_native_password', exists => 1, hashed => 0 );
        push @sql, $self->get_disable_auth_plugin_sql( quoted_user => $quoted_user, force_plugin => 1 );
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

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MySQL::MySQL55

=head1 SYNOPSIS

The database module for MySQL 5.5

=head1 DESCRIPTION

This module contains all code and attributes unique to MySQL 5.5

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

=head1 METHODS

=over

=item * new -- Returns a blessed object.

=item * get_set_password_sql -- Returns the sql statement to set the password for a user.

=back
