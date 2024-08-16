package Cpanel::Database::MySQL::MySQL56;

# cpanel - Cpanel/Database/MySQL/MySQL56.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::ConfigFiles ();
use Cpanel::Database    ();

use parent 'Cpanel::Database::MySQL';

use constant {
    supported           => 1,
    recommended_version => 0,
    short_version       => '56',
    item_short_version  => '5.6',
    selected_version    => 'MySQL56',
    locale_version      => 'MySQL 5.6',
    eol_time            => {
        start => 1360022400,
        end   => 1612483200
    },
    release_notes => 'https://go.cpanel.net/changes-mysql56',
    features      => [
        'Improved optimizer for all-around query performance.',
        'Improved [asis,InnoDB] for higher transactional throughput.',
        'New [asis,NoSQL]-style [asis,memcached] [asis,API]s.',
        'Improved partitioning that helps query and manage huge tables.',
        'Several replication improvements.',
        'Expanded the data available through PERFORMANCE_SCHEMA, and improved performance monitoring.',
        'Does not support the User Statistics feature.',
    ],
    prefix_length            => 8,
    max_dbuser_length        => 16,
    default_sql_mode         => 'NO_ENGINE_SUBSTITUTION',
    general_upgrade_warnings => [],
    config_upgrade_warnings  => [
        {
            config  => { key => 'userstat', value => qr/(on|1)/i, },
            warning => {
                severity => 'Fatal',
                message  => "The <em>userstat</em> setting is currently enabled in the $Cpanel::ConfigFiles::MYSQL_CNF file.\n<br /><br />\nThe cPanel-provided distribution of MySQL® does not support this setting. You must either remove the userstat option from the $Cpanel::ConfigFiles::MYSQL_CNF file before you upgrade MySQL, or defer the upgrade until this setting becomes supported.",
            },
        },
    ],
    is_eol => 1,
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
        push @sql, $self->get_password_unexpire_sql( quoted_user => $quoted_user, quoted_host => Cpanel::MysqlUtils::Quote::quote($localhost) );
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

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    my @warnings = ();

    my $installed_version = $opts{'from_version'};

    # Fatal because it stops new cPanel accounts from being properly created.
    if ( $installed_version <= 5.6 && $self->_is_usemysqloldpass_enabled() ) {
        push @warnings, {
            'severity' => 'Fatal',
            'message'  =>
              "The <em>Use pre-4.1-style MySQL® passwords</em> setting on your server is currently enabled.\n<br /><br />\nThis configuration is not supported in MySQL 5.6 and later. You will need to disable pre-4.1-style MySQL passwords before you upgrade to MySQL 5.6 and later. Failure to disable pre-4.1-style MySQL passwords may prevent the creation of new MySQL accounts after you upgrade. The “Use pre-4.1-style MySQL® passwords” Tweak Setting controls this setting.",
        };
    }

    return @warnings;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MySQL::MySQL56

=head1 SYNOPSIS

The database module for MySQL 5.6

=head1 DESCRIPTION

This module contains all code and attributes unique to MySQL 5.6

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

=head1 METHODS

=over

=item * new -- Returns a blessed object.

=item * get_set_password_sql -- Returns the sql statement to set the password for a user.

=back
