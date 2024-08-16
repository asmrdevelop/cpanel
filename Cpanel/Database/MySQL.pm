package Cpanel::Database::MySQL;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;
use Cpanel::Database            ();
use Cpanel::MysqlUtils::Connect ();
use Cpanel::OS                  ();

use constant {
    type                                  => 'MySQL',
    user                                  => 'mysql',
    default_plugin                        => 'mysql_native_password',
    fetch_temp_users_key_field            => 'user',
    auth_field                            => 'Password',
    daemon_name                           => 'mysqld',
    service_name                          => 'mysqld',
    possible_service_names                => [ 'mysql', 'mysqld' ],
    populate_password_column              => 0,
    experimental                          => 0,
    prefix_length                         => 16,
    max_dbuser_length                     => 32,
    uses_release_rpm                      => 1,
    is_eol                                => 0,
    has_public_grants                     => 0,
    default_sql_mode                      => 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION',
    default_innodb_buffer_pool_chunk_size => 134217728,
    min_innodb_buffer_pool_chunk_size     => 1048576,
    config_upgrade_warnings               => [
        {
            config  => { key => 'innodb_force_recovery', value => qr/[1-9]/, },
            warning => {
                severity => 'Fatal',
                message  => "The system detected that the “innodb_force_recovery” setting is enabled in the “/etc/my.cnf” file. This issue may interfere with the upgrade.",
            }
        },
    ],
};

sub new ( $class, $self = {} ) {
    return bless( $self, $class );
}

sub validate_config_options ( $self, $cnf ) {
    return [ "--defaults-file=$cnf", '--help', '--verbose' ];
}

sub get_repo ($self) {
    my $short_version = $self->item_short_version;

    # Don't return a repo unless this OS is supposed to use this facility.
    return '' unless Cpanel::OS::list_contains_value( 'mysql_versions_use_repo_template', $short_version );

    my $flat_version = $short_version;
    $flat_version =~ s/\.//;

    my $distro_major = Cpanel::OS::major();                 ## no critic(Cpanel::CpanelOS) major is used by templates
    my $repo_content = Cpanel::OS::mysql_repo_template();
    $repo_content =~ s/###DISTRO_MAJOR###/$distro_major/g;
    $repo_content =~ s/###MYSQL_VERSION_SHORT###/$short_version/g;
    $repo_content =~ s/###MYSQL_FLAT_VERSION_SHORT###/$flat_version/g;
    return $repo_content;
}

sub get_set_password_sql ( $self, %opts ) {

    my @missing_args = grep { !exists $opts{$_} } (qw/ name pass exists hashed plugin /);
    die "Missing needed arguments: " . join( ",", @missing_args ) if @missing_args;

    my $has_pass = ( $opts{pass} && $opts{pass} ne 'NULL' );

    my $power_word = $opts{exists} ? 'ALTER USER IF EXISTS' : 'CREATE USER';

    my $sql = "$power_word $opts{name}";

    if ($has_pass) {

        $sql .= " IDENTIFIED ";
        $sql .= $opts{hashed} ? "WITH $opts{plugin} AS " : 'BY ';
        $sql .= "$opts{pass};";

    }
    else {

        $sql .= ';';

    }

    $sql .= " $opts{'method'} USAGE ON *.* TO $opts{name};" if $opts{'method'};

    # See t/Cpanel-Mysql-Create.t test___user_and_grant_management_cb() to see what this sql is expected to look like.
    return $sql;
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

sub set_user_resource_limits ( $self, %opts ) {
    my $sql  = $self->get_set_user_resource_limits_sql(%opts);
    my $rows = $self->_do($sql);
    $self->_do("FLUSH PRIVILEGES;");

    return 1;
}

sub get_enable_default_auth_plugin_sql ( $self, %opts ) {

    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host}   ? qq{ AND Host = $quoted_host_or_bind} : q{};
    my $nice_plugin_change  = $opts{force_plugin} ? ''                                   : " AND (plugin = '' OR plugin = null OR plugin = 'mysql_old_password' OR plugin = 'auth_socket')";
    my $plugin              = $self->default_plugin;

    return qq{UPDATE mysql.user SET plugin = '$plugin' WHERE User = $quoted_user_or_bind$host_string$nice_plugin_change;};
}

sub get_disable_auth_plugin_sql ( $self, @ ) {
    return qq{};    # Not supported
}

sub get_password_lifetime_sql ( $self, %opts ) {
    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host} ? qq{ AND Host = $quoted_host_or_bind} : q{};

    return qq{UPDATE mysql.user SET password_lifetime=0 WHERE User = $quoted_user_or_bind$host_string;};
}

sub get_password_unexpire_sql ( $self, %opts ) {
    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host} ? qq{ AND Host = $quoted_host_or_bind} : q{};

    return qq{UPDATE mysql.user SET password_expired='N' WHERE User = $quoted_user_or_bind$host_string;};
}

sub get_root_pw_init_file_sql ( $self, $quoted_password ) {

    require Cpanel::MysqlUtils::Reset;
    require Cpanel::MysqlUtils::Quote;

    my @sql = ();

    for my $localhost ( Cpanel::Database::_localhosts_for_root_user() ) {
        my $fullname = $self->_get_quoted_user( 'user' => 'root', 'host' => $localhost );

        push @sql, "CREATE USER IF NOT EXISTS $fullname;";
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

sub user_exists ( $self, $user, $host ) {
    return qq{SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = $user and host = $host);};
}

sub get_hosts ($self) {
    require Cpanel::ArrayFunc::Uniq;
    $self->_acquire_dbh();
    return Cpanel::ArrayFunc::Uniq::uniq( map { $_->[0] } $self->{'dbh'}->selectall_arrayref(qq{SELECT Host FROM mysql.user;})->@* );
}

sub get_local_hosts ($self) {
    require Cpanel::IP::Loopback;
    return grep { Cpanel::IP::Loopback::is_loopback($_) } $self->get_hosts();
}

sub get_remote_hosts ($self) {
    require Cpanel::IP::Loopback;
    return grep { !Cpanel::IP::Loopback::is_loopback($_) } $self->get_hosts();
}

sub search_mysqlusers ( $self, $condition ) {
    return if $condition =~ m/;/g;
    $self->_acquire_dbh();
    return [ map { { 'user' => $_->[0], 'host' => $_->[1] } } $self->{'dbh'}->selectall_arrayref(qq{SELECT User,Host FROM mysql.user WHERE $condition;})->@* ];
}

sub revoke_privs ( $self, %opts ) {
    my $account_name = $self->_get_quoted_user( 'user' => $opts{'user'}, 'host' => $opts{'host'} );
    my $privs        = join( ', ', $opts{'privs'}->@* );
    return $self->_do(qq{REVOKE $privs ON $opts{'on'} TO $account_name;});
}

sub get_remove_users_sql ( $self, $user_arrayref ) {
    return 0 unless scalar( $user_arrayref->@* );

    my $users = join( ", ", map { $self->_get_quoted_user( 'user' => $_->{'user'}, 'host' => $_->{'host'} ) } $user_arrayref->@* );
    return qq{DROP USER $users;};
}

sub remove_users ( $self, $user_arrayref ) {
    return 0 unless ref($user_arrayref) eq 'ARRAY';
    return 0 unless scalar( $user_arrayref->@* );

    my ( $output, $error ) = $self->_do( $self->get_remove_users_sql($user_arrayref) );

    if ($error) {
        require Cpanel::Mysql::Error;

        # Handle users that exist in mysql.user table but are no longer active (ER_CANNOT_USER HY000 1396)
        my $error_code = $error->get('error_code');
        if ( $error_code == Cpanel::Mysql::Error::ER_CANNOT_USER() ) {
            $self->remove_user_from_global_priv( 'user' => $_->{'user'}, 'host' => $_->{'host'} ) for $user_arrayref->@*;
        }
        else {
            warn "MySQL Error ($error_code): $error\n";
        }
    }
    return 1;
}

sub remove_user_from_generic_priv ( $self, %opts ) {
    return $self->_do( qq{DELETE FROM mysql.$opts{'table'} WHERE User='$opts{'user'}'} . ( $opts{'host'} ? qq{ AND Host='$opts{'host'}';} : ';' ) );
}

sub remove_user_from_global_priv ( $self, %opts ) {
    return $self->remove_user_from_generic_priv( %opts, 'table' => 'user' );
}

sub remove_user_from_db_priv ( $self, %opts ) {
    return $self->remove_user_from_generic_priv( %opts, 'table' => 'db' );
}

sub remove_user_from_tables_priv ( $self, %opts ) {
    return $self->remove_user_from_generic_priv( %opts, 'table' => 'tables_priv' );
}

sub remove_user_from_columns_priv ( $self, %opts ) {
    return $self->remove_user_from_generic_priv( %opts, 'table' => 'columns_priv' );
}

sub get_config_upgrade_warnings ( $self, %opts ) {
    my $installed_version = $opts{'from_version'};
    my $target_version    = $self->item_short_version;

    my @conf_warnings = $self->config_upgrade_warnings->@*;
    push( @conf_warnings, Cpanel::Database::MySQL->config_upgrade_warnings->@* );

    $self->_handle_multi_gen_upgrades(
        $installed_version, $target_version,
        sub ($intermediate_module) {
            push( @conf_warnings, $intermediate_module->config_upgrade_warnings->@* );
        }
    );

    return @conf_warnings;
}

sub revoke_default_public_grants ($self) {
    die 'MySQL does not support public grants';
}

sub get_upgrade_warnings ( $self, %opts ) {
    my @warnings = ();

    my $installed_version = $opts{'from_version'};
    my $installed_type    = $opts{'from_type'};
    my $target_version    = $self->item_short_version;
    my $target_type       = $self->type;

    require Cpanel::Version::Compare;

    my $is_multi_gen = $self->_handle_multi_gen_upgrades(
        $installed_version, $target_version,
        sub ($intermediate_module) {
            push( @warnings, $intermediate_module->general_upgrade_warnings->@*, $intermediate_module->_get_dynamic_upgrade_warnings(%opts) );
        }
    );

    if ($is_multi_gen) {
        push @warnings,
          {
            'severity' => 'Normal',
            'message'  => "The selected $target_type version ($target_version) is more than one generation newer than the currently installed version. The upgrade process will iterate over each intervening version to ensure tables are upgraded appropriately.",
          };
    }

    if ( Cpanel::Version::Compare::compare( $target_version, '<', $installed_version ) ) {
        push @warnings,
          {
            'severity' => 'Fatal',
            'message'  => "The selected $target_type version ($target_version) is older than the currently installed $installed_type version ($installed_version). Downgrades using this interface are not supported."
          };
    }

    if ( $target_version eq $installed_version ) {
        push @warnings,
          {
            'severity' => 'Normal',
            'message'  => "The selected $target_type version ($target_version) is the same as the currently installed $installed_type version ($installed_version). No upgrade will be performed at this time, though the normal upgrade steps will still be executed. This is only useful if a previous upgrade failed while partially completed."
          };
    }

    push( @warnings, Cpanel::Database::MySQL->_get_dynamic_upgrade_warnings(%opts) );
    push( @warnings, $self->_get_dynamic_upgrade_warnings(%opts) );
    return @warnings;
}

sub _handle_multi_gen_upgrades ( $self, $installed, $target, $sub ) {
    require Cpanel::MysqlUtils::Versions;
    require Cpanel::MariaDB;

    my @update_path = grep { $_ ne $installed } Cpanel::MysqlUtils::Versions::get_upgrade_path_for_version( $installed, $target );

    for my $intermediate_version ( grep { $_ ne $target } @update_path ) {
        my $intermediate_type   = Cpanel::MariaDB::version_is_mariadb($intermediate_version) ? 'MariaDB' : 'MySQL';
        my $intermediate_module = Cpanel::Database->new( { 'reset' => 1, 'db_type' => $intermediate_type, 'db_version' => $intermediate_version, } );
        $sub->($intermediate_module);
        Cpanel::Database::reset_singleton();
    }

    # used to set $is_multi_gen
    if ( scalar(@update_path) > 1 ) {
        return 1;
    }
    return 0;
}

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    return ();    # To be defined in versioned modules.
}

sub _is_usemysqloldpass_enabled ($self) {
    require Cpanel::Config::LoadCpConf;

    # Check whether the tweak setting is enabled
    my $conf = Cpanel::Config::LoadCpConf::loadcpconf();
    return $conf->{'usemysqloldpass'} ? 1 : 0;
}

sub _do ( $self, @args ) {
    my ( $output, $error );
    $self->_acquire_dbh();
    eval { $output = $self->{'dbh'}->do(@args); };
    $error = $@ if $@;
    return ( $output, $error );
}

sub _db_exists ( $self, $db ) {
    my ( $db_exists, $error );

    $self->_acquire_dbh();
    eval { $db_exists = $self->{'dbh'}->db_exists($db) ? 1 : 0; };
    $error = $@ if $@;

    return ( $db_exists, $error );
}

sub _get_quoted_user ( $self, %opts ) {
    require Cpanel::MysqlUtils::Quote;
    my $q_user = Cpanel::MysqlUtils::Quote::quote( $opts{'user'} );
    my $q_host = $opts{'host'} ? Cpanel::MysqlUtils::Quote::quote( $opts{'host'} ) : undef;
    return $q_user . ( $q_host ? '@' . $q_host : '' );
}

sub _acquire_dbh ($self) {
    $self->{'dbh'} //= Cpanel::MysqlUtils::Connect::get_dbi_handle();
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::Database::MySQL

=head1 SYNOPSIS

The database module for MySQL

=head1 DESCRIPTION

This module contains all code and attributes unique to MySQL

=head1 METHODS

=over

=item * new -- Returns a blessed object.

=item * validate_config_options -- Returns the options required to pass to mysqld to validate my.cnf

=item * get_repo -- Returns the yum repo configuration for the running MySQL version.

=item * get_set_password_sql -- Returns the sql statement to set the password for a user.

=over

Arguments:

name (String) -- Required -- The name of the sql user to set the password for. MUST be in a "$user@$host" form
with user and host already properly quoted.

pass (String) -- Required -- The password to set for the user.

exists (Bool) -- Required -- Set to true if the user already exists. This determines if we "ALTER USER" or "CREATE USER".

hashed (Bool) -- Required -- Set to true if the password is already hashed.

plugin (String) -- Required -- The authentication plugin to use. This is needed if the password is already hashed.

method (String) -- Optional -- Can only be 'GRANT' or 'REVOKE'. Only set this if you want to grant or revoke usage on all database and tables for the user.

=back

=item * set_user_resource_limits -- Updates user resource limits on mysql.user table.

=over

Arguments:

max_user_connections (Int/String) -- Optional -- The maximum number of simultaneous connections permitted for the database user.

max_updates (Int/String) -- Optional -- The maximum number of updates permitted per hour for the database user.

max_connections (Int/String) -- Optional -- The maximum number of simultaneous connections permitted per hour for the database user.

max_questions (Int/String) -- Optional -- The maximum number of questions permitted per hour for the database user.

user (String) -- Required -- The user to alter.

host (String) -- Optional -- The host to alter.

=back

=item * get_set_user_resource_limits_sql -- Returns the sql to update resource limits.

=over

Arguments: Takes the same arguments as set_user_resource_limits(). This method returns the sql that set_user_resource_limits() executes.

=back

=item * get_enable_default_auth_plugin_sql -- Returns the sql to enable the default authentication plugin.

=over

Arguments:

quoted_user (String) -- Optional -- The user as an already quoted string. Defaults to the bind variable, '?'.

quoted_host (String) -- Optional -- The host as an already quoted string. Defaults to the bind variable, '?'.

needs_host (Bool) -- Optional -- Determines if we need to do the loopup with the host.

force_plugin (Bool) -- Optional -- If set to true, it will force the plugin value to default no matter what the existing value is.
                                   Without force, the plugin will only be updated if it is not set or equal to 'mysql_old_password'.

=back

=item * get_disable_auth_plugin_sql -- Returns the sql to disable the authentication plugin. Needs to be defined for MySQL 5.5.

=item * get_password_lifetime_sql -- Returns the sql to ensure the password lifetime is disabled.

=over

Arguments:

quoted_user (String) -- Optional -- The user as an already quoted string. Defaults to the bind variable, '?'.

quoted_host (String) -- Optional -- The host as an already quoted string. Defaults to the bind variable, '?'.

needs_host (Bool) -- Optional -- Determines if we need to do the loopup with the host.

=back

=item * get_password_unexpire_sql -- Returns the sql to ensure the users password is not expired.

=over

Arguments:

quoted_user (String) -- Optional -- The user as an already quoted string. Defaults to the bind variable, '?'.

quoted_host (String) -- Optional -- The host as an already quoted string. Defaults to the bind variable, '?'.

needs_host (Bool) -- Optional -- Determines if we need to do the loopup with the host.

=back

=item * get_root_pw_init_file_sql -- Returns the sql used to reset the root user's password when using an init file.

=over

Arguments:

quoted_password (String) -- Required -- The password to reset the root password to. Must already be properly quoted if needed.

=back

=item * user_exists -- Returns the sql to check if a user exists.

=over

Arguments:

user (String) -- Required -- The user to search for.

host (String) -- Required -- The host of the user to search for.

=back

=back
