package Whostmgr::Mysql::Workarounds;

# cpanel - Whostmgr/Mysql/Workarounds.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Init::Simple        ();
use Cpanel::LoadModule          ();
use Cpanel::MysqlUtils::Connect ();
use Cpanel::MysqlUtils::Compat  ();
use Cpanel::MariaDB             ();
use Cpanel::MysqlUtils::Version ();
use Cpanel::Database            ();

use Try::Tiny;

#
#Returns 1 or 0, indicating whether this did any work or not.
#
sub disable_password_validation_plugin {
    my ($dbh) = @_;

    if ( Cpanel::MysqlUtils::Compat::has_validate_password_support() ) {
        $dbh ||= Cpanel::MysqlUtils::Connect::get_dbi_handle();
        if ( Cpanel::MysqlUtils::Compat::validate_password_is_component() ) {
            try {

                # https://dev.mysql.com/doc/refman/8.0/en/validate-password.html
                # https://dev.mysql.com/doc/refman/8.0/en/component-loading.html
                $dbh->do(q{UNINSTALL COMPONENT 'file://component_validate_password';});
            }
            catch {
                Cpanel::LoadModule::load_perl_module('Cpanel::Mysql::Error');

                # Unloading a component that is already unloaded produces the error ER_COMPONENTS_UNLOAD_NOT_LOADED in MySQL
                die $_ if $dbh->err() ne Cpanel::Mysql::Error::ER_COMPONENTS_UNLOAD_NOT_LOADED();
            };
        }
        else {
            try {
                $dbh->do(q{uninstall plugin validate_password});
            }
            catch {
                Cpanel::LoadModule::load_perl_module('Cpanel::Mysql::Error');

                #ER_SP_DOES_NOT_EXIST is given if a function or stored procedure doesn't exist
                # it's also given if the plugin we try to uninstall doesn't exist.
                die $_ if $dbh->err() ne Cpanel::Mysql::Error::ER_SP_DOES_NOT_EXIST();
            };
        }
        return 1;
    }

    return 0;
}

# Case CPANEL-21573: MySQL 5.7 dropped the password column, so we need to copy the
# authentication_string over into it when upgrading to MariaDB.
#
# MariaDB 10.5 no longer needs this workaround.
sub populate_mariadb_password_column {
    my ($dbh) = @_;

    return 0 if !Cpanel::Database->new( { reset => 1 } )->populate_password_column();

    if ( Cpanel::MysqlUtils::Compat::has_old_password_support() ) {
        $dbh ||= Cpanel::MysqlUtils::Connect::get_dbi_handle();
        $dbh->do(
            q<
                UPDATE mysql.user
                SET Password = authentication_string
                WHERE plugin = 'mysql_native_password' AND Password = ''
            >,
        );

        $dbh->do('FLUSH PRIVILEGES');

        return 1;
    }

    return 0;
}

# CPANEL-27816: MariaDB was not correctly enabling itself with systemd on upgrades.
# This subroutine exists to ensure that it is enabled.
sub enable_maria_systemd_service {

    my $current_version = Cpanel::MysqlUtils::Version::current_mysql_version();
    return 0 unless Cpanel::MariaDB::version_is_mariadb( $current_version->{'short'} );

    Cpanel::Init::Simple::call_cpservice_with( 'mariadb' => 'enable' );

    return;
}

# CPANEL-38157: When doing upgrades from MySQL to MariaDB it is possible to get invalid
# data in the password_last_changed column. This workaround is intended to fix this problem
# until MariaDB releases an offical fix.
#
# The MariaDB bug is being tracked with: https://jira.mariadb.org/browse/MDEV-26363
# This workaround can be removed once that bug is fixed and released to the public.
#
sub fix_mariadb_last_changed_password {
    my ($dbh) = @_;

    my $current_version = Cpanel::MysqlUtils::Version::current_mysql_version();
    return 0 unless Cpanel::MariaDB::version_is_mariadb( $current_version->{'short'} );

    $dbh ||= Cpanel::MysqlUtils::Connect::get_dbi_handle();

    my $query;

    if ( $current_version->{'short'} > 10.3 ) {
        $query = "UPDATE mysql.global_priv SET Priv=JSON_SET(Priv, '\$.password_last_changed', UNIX_TIMESTAMP()) WHERE JSON_VALUE(Priv, '\$.password_last_changed') = '0'";
    }
    else {
        $query = "UPDATE mysql.user SET password_last_changed = NOW() WHERE password_last_changed = '0000-00-00 00:00:00'";
    }

    eval { $dbh->do($query); };
    eval { $dbh->do('FLUSH PRIVILEGES'); };

    return 1;
}

1;
