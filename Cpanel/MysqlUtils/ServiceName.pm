package Cpanel::MysqlUtils::ServiceName;

# cpanel - Cpanel/MysqlUtils/ServiceName.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::MysqlUtils::Version ();
use Cpanel::OS                  ();

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::ServiceName - Determine the systemd or initd service name for the installed mysql.

=head1 SYNOPSIS

    use Cpanel::MysqlUtils::ServiceName ();

    my $service_name = Cpanel::MysqlUtils::ServiceName::get_installed_version_service_name();


=head2 get_installed_version_service_name()

Return the service name that is in use for the currently installed
mysql in order to know which service the system should interact with
using initd or systemd scripts.

=cut

sub get_installed_version_service_name {

    return 'mysql' unless Cpanel::OS::is_systemd();

    my $version = Cpanel::MysqlUtils::Version::get_local_mysql_version_with_fallback_to_default();

    # Just using the version won't be a viable choice much longer, and Ubuntu already makes it
    # a non-starter since the service has a different name on Ubuntu and the CentOS and friends' mysql installs

    if ( Cpanel::MysqlUtils::Version::is_at_least( $version, '10.1' ) ) {
        return 'mariadb';
    }
    elsif ( Cpanel::MysqlUtils::Version::is_at_least( $version, '10.0' ) ) {
        if ( -f '/lib/systemd/system/mysql.service' ) {
            return 'mysql';
        }
        if ( -f '/usr/lib/systemd/system/mysqld.service' ) {
            return 'mysqld';
        }
        return 'mysql';
    }
    elsif ( Cpanel::MysqlUtils::Version::is_at_least( $version, '5.7' ) ) {
        if ( -f '/lib/systemd/system/mysql.service' ) {
            return 'mysql';
        }
        if ( -f '/usr/lib/systemd/system/mysqld.service' ) {
            return 'mysqld';
        }
        return 'mysqld';
    }

    return 'mysql';
}
1;
