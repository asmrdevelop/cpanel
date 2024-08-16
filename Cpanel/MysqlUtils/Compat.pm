package Cpanel::MysqlUtils::Compat;

# cpanel - Cpanel/MysqlUtils/Compat.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MysqlUtils::Version ();
use Cpanel::Debug               ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Compat - Determine which features the installed mysql supports

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::Compat ();

    my $mysql_user_auth_field = Cpanel::MysqlUtils::Compat::get_mysql_user_auth_field();

    my $has_old_password_support = Cpanel::MysqlUtils::Compat::has_old_password_support();

    my $has_password_lifetime_support = Cpanel::MysqlUtils::Compat::has_password_lifetime_support();

    my $has_password_expired_support = Cpanel::MysqlUtils::Compat::has_password_expired_support();

    my $needs_password_plugin_disabled = Cpanel::MysqlUtils::Compat::needs_password_plugin_disabled();

    my $get_information_schema_stats_expiry_sql = Cpanel::MysqlUtils::Compat::get_information_schema_stats_expiry();

=head1 DESCRIPTION

This module is used to determine which features and workarounds the installed
mysql version needs.

=cut

=head2 get_mysql_user_auth_field()

Returns SQL for the password hash in the mysql.user table.

For most versions that’s just a column name; however, for MariaDB 10.2+
it’s an SQL expression. That means that for those DB versions, the return
of this function B<CANNOT> be use as the name of a column to assign to, e.g.,
in a SET or UPDATE command.

In all contexts, though, the return of this function is safe to use in a
WHERE clause.

=cut

sub get_mysql_user_auth_field {
    my $mysql_version = _long_mysql_version_or_default();

    require Cpanel::MysqlUtils::Support;

    if ( Cpanel::MysqlUtils::Support::server_uses_mariadb_ambiguous_SET_PASSWORD($mysql_version) ) {
        return q<IF( LENGTH(Plugin), authentication_string, Password )>;
    }

    return Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.0.0' ) ? 'Password' :    # MariaDB
      Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.7.0' )
      ? 'authentication_string'                                                                   # MySQL 5.7+
      : 'Password';                                                                               # <  MySQL 5.7
}

=head2 has_old_password_support()

Returns 1 if the the installed mysql supports the OLD_PASSWORD() function. Returns 0 if it does not.

=cut

sub has_old_password_support {

    # Thus far, even MariaDB 10.3 retains the OLD_PASSWORD() function.
    my $mysql_version = _long_mysql_version_or_default();
    return 1 if Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.0.0' );

    return get_mysql_user_auth_field() eq 'Password' ? 1 : 0;
}

=head2 has_password_lifetime_support()

Returns 1 if the the installed mysql has the password_lifetime column in the mysql.user table.
Returns 0 if it does not.

=cut

sub has_password_lifetime_support {
    my $mysql_version = _long_mysql_version_or_default();

    return 0 if Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.0.0' );
    return 1 if Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.7.0' );
    return 0;
}

=head2 has_password_expired_support()

Returns 1 if the the installed mysql has the password_expired column in the mysql.user table.
Returns 0 if it does not.

=cut

sub has_password_expired_support {
    my $mysql_version = _long_mysql_version_or_default();

    return 1 if Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.6.0' );
    return 0;
}

=head2 needs_password_plugin_disabled()

Returns 1 if the the installed mysql needs the workaround to disable
the mysql_native_password or mysql_old_password plugins. Returns 0 if it does not.

For more information see _dbowner_to_all_without_ownership_checks in
Cpanel::Mysql

=cut

sub needs_password_plugin_disabled {
    my $mysql_version = _long_mysql_version_or_default();

    return Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.2.0' ) ? 0 :      # MariaDB 10.2+
      Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.1.0' )      ? 1 :      # MariaDB 10.1 is the only MariaDB version that needs plugin remova
      Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.7.0' )       ? 0 :      # MySQL 5.7+
      Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.5.7' )       ? 1 : 0;
}

=head2 has_plugin_support()

Returns 1 if the the installed mysql has authentication plugin support. Returns 0 if it does not.

=cut

sub has_plugin_support {
    my $mysql_version = _long_mysql_version_or_default();

    return Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.5' ) ? 1 : 0;
}

=head2 has_validate_password_support()

Returns 1 if the the installed mysql has validate_password plugin support. Returns 0 if it does not.

=cut

sub has_validate_password_support {
    my $mysql_version = _long_mysql_version_or_default();

    # https://dev.mysql.com/doc/refman/5.6/en/validate-password-plugin.html
    return Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.0.0' ) ? 0 :       # MariaDB
      Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.6.6' )       ? 1 : 0;    # MySQL 5.6.6+
}

=head2 validate_password_is_component()

Returns 1 if the the installed mysql has validate_password component support. Returns 0 if it does not.

=cut

sub validate_password_is_component {
    my $mysql_version = _long_mysql_version_or_default();

    if ( Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '8.0.0' ) ) {
        require Cpanel::MariaDB;
        return Cpanel::MariaDB::version_is_mariadb($mysql_version) ? 0 : 1;
    }

    return 0;
}

=head2 apply_limits_to_systemd_unit()

Returns 1 if the the installed MariaDB uses the systemd file for limits instead of or in addition to /etc/my.cnf. Returns 0 if it does not.
Not all versions need to apply limits to the systemd file as some are just wrappers around the previous init scripts or mysqld_safe. Since
those start as root, they don't need elevated permissions to increase the limits.

See:

https://mariadb.com/kb/en/library/systemd/
https://mariadb.com/kb/en/library/server-system-variables/
https://dev.mysql.com/doc/refman/5.7/en/using-systemd.html

=cut

sub apply_limits_to_systemd_unit {
    my $mysql_version = _long_mysql_version_or_default();
    return
        Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.1.0' ) ? 1
      : Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.0.0' ) ? 0
      :                                                                                # MariaDB still used the mysql.service unit file that was a shim around the init script exclusively in 10.0
      Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.7.10' ) ? 1 : 0;    # MySQL 5.7 improved support for systemd
}

=head2 get_systemd_service_name()

This function returns the systemd service name based upon the current MySQL or MariaDB version. The return will be one of 'mysql', 'mariadb', or 'mysqld'.

See:

https://mariadb.com/kb/en/library/systemd/
https://mariadb.com/kb/en/library/server-system-variables/
https://dev.mysql.com/doc/refman/5.7/en/using-systemd.html

=cut

=head2 mysqld_supports_initialize()

Returns 1 if the the installed mysqld supports the --initalize flag
Returns 0 if it does not.

=cut

sub mysqld_supports_initialize {
    my $mysql_version = _long_mysql_version_or_default();

    # As of this writing, no MariaDB version (including the 10.4 RC)
    # appears to support “mysqld --initialize”.
    return 0 if Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.0.0' );
    return 1 if Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.7.6' );
    return 0;
}

sub get_systemd_service_name {
    my $mysql_version = _long_mysql_version_or_default();

    return
        Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.1.0' ) ? 'mariadb'
      : Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '10.0.0' ) ? 'mysql'
      :                                                                                            # MariaDB still used the mysql.service unit file that was a shim around the init script exclusively in 10.0
      Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '5.7.0' ) ? 'mysqld' : 'mysql';    # MySQL 5.7 changed the service name in systemd
}

=head2 get_information_schema_stats_expiry()

Returns standalone SQL to set the information_schema_stats_expiry session variable, if applicable.
Returns an empty string if not applicable.

In MySQL 8.0.3 information_schema_stats_expiry was introduced with a default of 24 hours.
information_schema_stats_expiry=0 can be used to always query the latest data but prevents caching the gathered data for future use.
Because stats expiry is determined on a per-query basis based on the last update time, using a relatively short expiry time here does not prevent future queries from taking advantage of the cache, up to the default information_schema_stats_expiry time.

See:

https://dev.mysql.com/doc/refman/8.0/en/server-system-variables.html#sysvar_information_schema_stats_expiry

=cut

sub get_information_schema_stats_expiry {
    my $mysql_version = _long_mysql_version_or_default();
    return q{} if Cpanel::MariaDB::version_is_mariadb($mysql_version);
    if ( Cpanel::MysqlUtils::Version::is_at_least( $mysql_version, '8.0.3' ) ) {
        return q{SET SESSION information_schema_stats_expiry=10;};
    }
    return q{};
}

sub _long_mysql_version_or_default {
    local $@;
    my $long_version = eval { Cpanel::MysqlUtils::Version::current_mysql_version()->{'long'} };

    if ($@) {

        # current_mysql_version has extensive logic to determine the current
        # version.  If it fails, MySQL is likely beyond repair and we need to reinstall.
        Cpanel::Debug::log_warn("All attempts to determine the currently installed MySQL/MariaDB version have failed. The system will assume the default version “$Cpanel::MysqlUtils::Version::DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED” is installed. The last error was: $@");
        return $Cpanel::MysqlUtils::Version::DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED;
    }

    return $long_version;
}

1;
