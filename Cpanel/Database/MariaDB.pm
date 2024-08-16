package Cpanel::Database::MariaDB;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

use cPstrict;
use Cpanel::Database            ();
use Cpanel::MysqlUtils::Connect ();
use Cpanel::OS                  ();

use constant {
    type                                  => 'MariaDB',
    user                                  => 'mysql',
    fetch_temp_users_key_field            => 'user',
    default_plugin                        => 'mysql_native_password',
    auth_field                            => 'Password',
    daemon_name                           => 'mysqld',
    service_name                          => 'mariadb',
    possible_service_names                => [ 'mysql', 'mysqld', 'mariadb' ],
    populate_password_column              => 0,
    experimental                          => 0,
    max_dbuser_length                     => 47,
    prefix_length                         => 16,
    uses_release_rpm                      => 0,
    is_eol                                => 0,
    has_public_grants                     => 0,
    default_sql_mode                      => 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION',
    default_innodb_buffer_pool_chunk_size => 134217728,
    min_innodb_buffer_pool_chunk_size     => 1048576,
    config_upgrade_warnings               => [
        {
            config  => { key => 'join_buffer', },
            warning => {
                severity => 'Fatal',
                message  => "The system detected that the “join_buffer” variable is present in the “/etc/my.cnf” file. This variable is not available with MariaDB, and must either be renamed to “join_buffer_size” or removed to continue with the upgrade",
            }
        },
        {
            config  => { key => 'innodb_force_recovery', value => qr/[1-9]/, },
            warning => {
                severity => 'Fatal',
                message  => "The system detected that the “innodb_force_recovery” setting is enabled in the “/etc/my.cnf” file. This issue may interfere with the upgrade.",
            }
        },
        {
            config  => { key => qr/read[-_]only/i, },
            warning => {
                severity => 'Fatal',
                message  => "Your database’s “read_only” flag is enabled. Disable this flag, then try again.",
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
    return '' unless Cpanel::OS::list_contains_value( 'mariadb_versions_use_repo_template', $short_version );

    my $flat_version = $short_version;
    $flat_version =~ s/\.//;

    my $distro_major = Cpanel::OS::major();    ## no critic(Cpanel::CpanelOS) major is used by templates

    my $repo_content = Cpanel::OS::mariadb_repo_template();
    $repo_content =~ s/###DISTRO_MAJOR###/$distro_major/g;
    $repo_content =~ s/###MARIADB_VERSION_SHORT###/$short_version/g;
    $repo_content =~ s/###MARIADB_FLAT_VERSION_SHORT###/$flat_version/g;
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

sub set_user_resource_limits ( $self, %opts ) {
    my $sql  = $self->get_set_user_resource_limits_sql(%opts);
    my $rows = $self->_do($sql);
    $self->_do("FLUSH PRIVILEGES;");

    return 1;
}

sub get_enable_default_auth_plugin_sql ( $self, %opts ) {

    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host} ? qq{ AND HOST = $quoted_host_or_bind} : q{};
    my $plugin              = $self->default_plugin;

    my $enable_auth_sql = qq{ALTER USER IF EXISTS $quoted_user_or_bind\@$quoted_host_or_bind IDENTIFIED WITH '$plugin';};

    if ( $opts{force_plugin} ) {
        return $enable_auth_sql;
    }

    $self->_acquire_dbh();
    my $current_plugin = $self->{'dbh'}->selectrow_array(qq{SELECT json_unquote(json_extract(priv, '\$.plugin')) FROM mysql.global_priv WHERE USER = $quoted_user_or_bind$host_string});

    if ( !$current_plugin || $current_plugin eq 'mysql_old_password' || $current_plugin eq '' || $current_plugin eq 'auth_socket' ) {
        return $enable_auth_sql;
    }

    # Nothing to do since we are not forcing the plugin change.
    return '';
}

sub get_disable_auth_plugin_sql ( $self, @ ) {
    return '';    # Not supported;
}

sub get_password_lifetime_sql ( $self, %opts ) {
    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    return qq{ALTER USER $quoted_user_or_bind\@$quoted_host_or_bind PASSWORD EXPIRE NEVER;};
}

sub get_password_unexpire_sql ( $self, %opts ) {
    my $quoted_user_or_bind = $opts{quoted_user} || '?';
    my $quoted_host_or_bind = $opts{quoted_host} || '?';
    my $host_string         = $opts{needs_host} ? qq{ AND Host = $quoted_host_or_bind} : q{};

    return qq{UPDATE mysql.global_priv SET priv=json_set(priv, '\$.password_expired', 'N') WHERE USER = $quoted_user_or_bind$host_string;};
}

sub get_root_pw_init_file_sql ( $self, $quoted_password ) {

    require Cpanel::MysqlUtils::Reset;
    require Cpanel::MysqlUtils::Quote;

    my @sql = ();

    for my $localhost ( Cpanel::Database::_localhosts_for_root_user() ) {
        my $fullname = $self->_get_quoted_user( 'user' => 'root', 'host' => $localhost );

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
    return qq{DROP USER IF EXISTS $users;};
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
    return $self->remove_user_from_generic_priv( %opts, 'table' => 'global_priv' );
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
    push( @conf_warnings, Cpanel::Database::MariaDB->config_upgrade_warnings->@* );

    $self->_handle_multi_gen_upgrades(
        $installed_version, $target_version,
        sub ($intermediate_module) {
            push( @conf_warnings, $intermediate_module->config_upgrade_warnings->@* );
        }
    );

    return @conf_warnings;
}

sub get_upgrade_warnings ( $self, %opts ) {
    my @warnings = ();

    my $installed_version = $opts{'from_version'};
    my $installed_type    = $opts{'from_type'};
    my $target_version    = $self->item_short_version;
    my $target_type       = $self->type;

    require Cpanel::Version::Compare;

    $self->_handle_multi_gen_upgrades(
        $installed_version, $target_version,
        sub ($intermediate_module) {
            push( @warnings, $intermediate_module->general_upgrade_warnings->@*, $intermediate_module->_get_dynamic_upgrade_warnings(%opts) );
        }
    );

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

    push( @warnings, Cpanel::Database::MariaDB->_get_dynamic_upgrade_warnings( %opts, 'to_version' => $target_version ) );
    push( @warnings, $self->_get_dynamic_upgrade_warnings(%opts) );
    return @warnings;
}

sub revoke_default_public_grants ( $self, $dbh ) {

    my @grants = eval {
        map { @$_ } $dbh->selectall_array(qq{SHOW GRANTS FOR PUBLIC});
    };
    return if !@grants;

    my $target_grants = {};
    $target_grants->{test_db}{regex}           = qr/^GRANT.+ON `test`\.\* TO PUBLIC$/i;
    $target_grants->{test_db}{revoke}          = qq{REVOKE ALL PRIVILEGES ON `test`.* FROM PUBLIC};
    $target_grants->{test_db_wildcard}{regex}  = qr/^GRANT.+ON `test\\_%`\.\* TO PUBLIC$/i;
    $target_grants->{test_db_wildcard}{revoke} = qq{REVOKE ALL PRIVILEGES ON `test\\_%`.* FROM PUBLIC};

    foreach my $target_grant ( keys $target_grants->%* ) {
        my $target = $target_grants->{$target_grant};
        if ( grep { $_ =~ $target->{regex} } @grants ) {
            $dbh->do( $target->{revoke} );
        }
    }

    return;
}

sub _handle_multi_gen_upgrades ( $self, $installed, $target, $sub ) {
    require Cpanel::MysqlUtils::Versions;
    require Cpanel::MariaDB;

    # this differs from upgrade path because we need to show the critical changes from each version
    # even though we don't install each version incrementally
    my @incremental_versions = grep { $_ ne $installed } Cpanel::MysqlUtils::Versions::get_incremental_versions( $installed, $target );

    for my $intermediate_version (@incremental_versions) {
        my $intermediate_type   = Cpanel::MariaDB::version_is_mariadb($intermediate_version) ? 'MariaDB' : 'MySQL';
        my $intermediate_module = Cpanel::Database->new( { 'reset' => 1, 'db_type' => $intermediate_type, 'db_version' => $intermediate_version, } );
        $sub->($intermediate_module);
        Cpanel::Database::reset_singleton();
    }

    return 1;
}

sub _get_dynamic_upgrade_warnings ( $self, %opts ) {
    my @warnings = ();

    my $installed_version = $opts{'from_version'};
    my $installed_type    = $opts{'from_type'};
    my $target_version    = $opts{'to_version'};

    require Cpanel::Version::Compare;

    # We want people to know that mysql_upgrade errors aren't always fatal, esp upgrading MySQL -> MariaDB 10.2
    if ( $installed_type eq 'MySQL' ) {

        # Fatal because it stops new cPanel accounts from being properly created.
        if ( Cpanel::Version::Compare::compare( $installed_version, '<=', '5.6' ) && _is_usemysqloldpass_enabled() ) {
            push @warnings, {
                'severity' => 'Fatal',
                'message'  =>
                  "The <em>Use pre-4.1-style MySQL® passwords</em> setting on your server is currently enabled.\n<br /><br />\nThis configuration is not supported in MySQL 5.6 and later. You will need to disable pre-4.1-style MySQL passwords before you upgrade to MySQL 5.6 and later. Failure to disable pre-4.1-style MySQL passwords may prevent the creation of new MySQL accounts after you upgrade. The “Use pre-4.1-style MySQL® passwords” Tweak Setting controls this setting.",
            };
        }

        if ( Cpanel::Version::Compare::compare( $target_version, '>=', '10.2' ) ) {
            push @warnings, {
                'severity' => 'Normal',
                'message'  => 'When you upgrade from MySQL® to MariaDB 10.2 or later, the mysql_upgrade utility may emit several database table-related errors. The discrepancies in the tables between MySQL and MariaDB versions produce the errors; however, the upgrade process will resolve these issues.'
            };
        }

        if ( Cpanel::Version::Compare::compare( $installed_version, '>=', '5.7' ) && Cpanel::Version::Compare::compare( $target_version, '<', '10.6' ) ) {
            push @warnings, {
                'severity' => 'Normal',
                'message'  => qq{MariaDB $target_version does <b>not</b> utilize the <a target="_blank" href="https://dev.mysql.com/doc/refman/5.7/en/sys-schema.html">sys schema</a>. If you upgrade from MySQL $installed_version to MariaDB $target_version, you <b>must</b> manually remove the sys database, because it can cause unnecessary errors during certain check table calls.},
            };
        }
    }

    return @warnings;
}

sub _is_usemysqloldpass_enabled () {
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

Cpanel::Database::MariaDB

=head1 SYNOPSIS

The database module for MariaDB

=head1 DESCRIPTION

This module contains all code and attributes unqiue to MariaDB

NOTE: Please refer to Cpanel::Database::MySQL for more indepth and complete POD!!

=head1 METHODS

=over

=item * new -- Returns a blessed object.

=item * validate_config_options -- Returns the options required to pass to mysqld to validate my.cnf

=item * get_repo -- Returns the yum repo configuration for the running MariaDB version.

=item * get_set_password_sql -- Returns the sql statement to set the password for a user.

=item * set_user_resource_limits -- Updates user resource limits on mysql.user table.

=back
