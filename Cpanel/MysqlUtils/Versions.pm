package Cpanel::MysqlUtils::Versions;

# cpanel - Cpanel/MysqlUtils/Versions.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::MariaDB ();
use Cpanel::Context ();
use Cpanel::OS      ();

## ================================
## To add a new version of MariaDB:
## ================================
## Add the new version to $UPGRADE_TARGETS_BY_VERSION and its respective supported versions sub
## Create the rpm files for the new version in /usr/local/cpanel/etc/rpm/*/yumrepo
## Add the new version to ULC/whostmgr/docroot/templates/mysqlupgrade/mysqlupgrade1.tmpl
## Add tests for the new version
## ================================

sub get_first_newstyle_mysql_version {
    return '5.7';
}

sub get_first_mariadb_version {
    return '10.0';
}

sub get_supported_mariadb_versions {
    return (qw{10.0 10.1 10.2 10.3 10.5 10.6 10.11});
}

sub get_supported_mysql_versions {
    return (qw{5.5 5.6 5.7 8.0});
}

sub get_versions {

    # must remain ordered for Whostmgr::Mysql::Upgrade::get_available_versions()
    # otherwise we could return keys %$UPGRADE_TARGETS_BY_VERSION;
    return (qw{4.1 5.0 5.1 5.5 5.6 5.7 8.0 10.0 10.1 10.2 10.3 10.4 10.5 10.6 10.11});
}

# list all versions that have been removed from rpm.versions
# these versions are completely blocked from any sort of GUI/automated help
my %DEPRECATED = ( '4.1' => 1, '5.0' => 1, '5.1' => 1 );

# each version can "upgrade" to itself (reinstall)
# we need 4.1+ in here so support can manage the upgrade process
# -- the GUI only gives the options for 5.5+
my $UPGRADE_TARGETS_BY_VERSION = {
    '4.1'   => [qw{5.5 5.6 5.7 10.5 10.6 10.11}],
    '5.0'   => [qw{5.5 5.6 5.7 10.5 10.6 10.11}],
    '5.1'   => [qw{5.5 5.6 5.7 10.5 10.6 10.11}],
    '5.5'   => [qw{5.5 5.6 5.7 10.5 10.6 10.11}],
    '5.6'   => [qw{5.6 5.7 10.5 10.6 10.11}],
    '5.7'   => [qw{5.7 8.0 10.5 10.6 10.11}],
    '8.0'   => [qw{8.0}],
    '10.0'  => [qw{10.0 10.5 10.6 10.11}],
    '10.1'  => [qw{10.1 10.5 10.6 10.11}],
    '10.2'  => [qw{10.2 10.5 10.6 10.11}],
    '10.3'  => [qw{10.3 10.5 10.6 10.11}],
    '10.4'  => [qw{10.4 10.5 10.6 10.11}],
    '10.5'  => [qw{10.5 10.6 10.11}],
    '10.6'  => [qw{10.6 10.11}],
    '10.11' => [qw{10.11}],
};

sub get_upgrade_targets ( $version = undef ) {
    if ( !$version ) {
        _die_trace("get_upgrade_targets requires a version");
    }
    return $UPGRADE_TARGETS_BY_VERSION->{$version};
}

sub get_incremental_versions ( $from_version = undef, $to_version = undef ) {
    if ( !( $from_version && $to_version ) ) {
        _die_trace("get_incremental_versions requires a from and to version");
    }
    my @versions = get_versions();

    require Cpanel::Version::Compare;
    return grep { Cpanel::Version::Compare::compare( $_, '>', $from_version ) && Cpanel::Version::Compare::compare( $_, '<=', $to_version ) } get_versions();
}

sub get_rpm_target_names (@versions) {
    Cpanel::Context::must_be_list();
    if ( !@versions ) { @versions = get_versions() }

    tr/.//d for @versions;

    return map { Cpanel::MariaDB::version_is_mariadb($_) ? "MariaDB$_" : "MySQL$_" } @versions;
}

sub get_vendor_for_version ( $version = undef ) {
    if ( !$version ) {
        _die_trace("get_vendor_for_version requires a version");
    }

    if ( Cpanel::MariaDB::version_is_mariadb($version) ) {
        return 'MariaDB';
    }
    elsif ( $version >= get_first_newstyle_mysql_version() ) {
        return 'Mysql';
    }

    return 'Mysql-legacy';
}

sub get_installable_versions {
    my %unsupported_db = map { $_ => 1 } @{ Cpanel::OS::unsupported_db_versions() };
    return grep { !$DEPRECATED{$_} && !$unsupported_db{$_} } get_versions();
}

sub get_installable_versions_for_version ( $current_version = undef ) {
    if ( !$current_version ) {
        _die_trace("get_installable_versions_for_version requires a version");
    }

    if ( !$UPGRADE_TARGETS_BY_VERSION->{$current_version} ) {
        _die_trace("get_installable_versions_for_version does not know about $current_version");
    }

    my %unsupported_db = map { $_ => 1 } @{ Cpanel::OS::unsupported_db_versions() };

    return grep { !$DEPRECATED{$_} && !$unsupported_db{$_} } @{ $UPGRADE_TARGETS_BY_VERSION->{$current_version} };
}

sub get_upgrade_path_for_version ( $current_version = undef, $want_version = undef ) {
    if ( !$current_version || !$want_version ) {
        _die_trace("get_upgrade_path_for_version requires a current_version and a want_version");
    }

    if ( !$UPGRADE_TARGETS_BY_VERSION->{$current_version} ) {
        _die_trace("get_upgrade_path_for_version does not know about $current_version");
    }

    my @upgrade_targets = @{ $UPGRADE_TARGETS_BY_VERSION->{$current_version} };

    # if the version is the same (i.e. reinstall)
    # or the requested version isn't in the available upgrade targets
    if ( $current_version eq $want_version || !grep { $_ eq $want_version } @upgrade_targets ) {
        return $current_version;
    }

    my $current_vendor = get_vendor_for_version($current_version);
    my $want_vendor    = get_vendor_for_version($want_version);

    # we do not need incremental upgrades for MariaDB
    if ( $want_vendor eq 'MariaDB' ) {
        return ($want_version);
    }

    require Cpanel::Version::Compare;
    return grep { Cpanel::Version::Compare::compare( $_, '>=', $current_version ) && Cpanel::Version::Compare::compare( $_, '<=', $want_version ) } @upgrade_targets;
}

sub _die_trace {
    require Cpanel::Carp;
    die Cpanel::Carp::safe_longmess(@_);
}

=pod

=head1 Cpanel::MySqlUtils::Versions

Cpanel::MySqlUtils::Versions -- version logic for MySQL and MariaDB upgrades

=head1 SYNOPSIS

    my @supported_versions = Cpanel::MySqlUtils::Versions::get_supported_mysql_versions()

=head1 DESCRIPTION

This module contains information on which versions are installable, which are
deprecated, can tell you what type of database a version number is, convert a
version number into a name that can be used for a yum install, and keeps track
of incremental upgrade paths.

=head2 B<get_first_newstyle_mysql_version()>

Returns the earliest "newstyle" MySQL version.

=head2 B<get_upgrade_targets( $version )>

Returns an array of versions that are possible to upgrade to from $version.
This does not account for system incompatibilities.

=head2 B<get_first_mariadb_version()>

Returns the first MariaDB version.

=head2 B<get_supported_mariadb_versions()>

Returns an array of MariaDB versions currently supported by cPanel.

=head2 B<get_supported_mysql_versions()>

Returns an array of MySQL versions currently supported by cPanel.

=head2 B<get_versions()>

Returns an array of cPanel-supported MySQL and MariaDB versions.

=head2 B<get_incremental_versions( $from_version, $to_version )>

Returns an array of cPanel-supported MySQL and MariaDB versions that exist
between $from_version and $to_version. This method was created to be able
to display critical warnings and changes from each version even when
incremental installation is not necessary for upgrade.

=head2 B<get_rpm_target_names ( @versions )>

Translates version numbers into RPM target names, e.g. "10.6" -> "MariaDB106".
When supplied with the @versions argument, it returns those numbers but translated
With no arguments, it returns a list of all supported versions in RPM name format.

=head2 B<get_vendor_for_version( $version )>

Returns the vendor name (e.g. MySQL, MariaDB) for $version.

=head2 B<get_installable_versions()>

Returns an array of versions which are not deprecated. This does not account for
system incompatibilities.

=head2 B<get_installable_versions_for_version( $version )>

Returns a list of versions which can theoretically be installed from $version.
This does not account for system incompatibilities.

=head2 B<get_upgrade_path_for_version( $current_version, $want_version )>

Returns an array of the versions you must install to upgrade from $current_version
to $want_version.

=cut

1;
