package Cpanel::MariaDB::Install;

# cpanel - Cpanel/MariaDB/Install.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PackMan ();
use Cpanel::YAML    ();    # PPI USE OK - Required for run_hooks (do not remove unless removing all calls to run_hooks())
use Cpanel::OS      ();
use Try::Tiny;

use parent 'Cpanel::Repo::Install::MysqlBasedDB';

=encoding utf-8

=head1 NAME

Cpanel::MariaDB::Install - The MariaDB installer

=head1 SYNOPSIS

    use Cpanel::MariaDB::Install ();

    my $obj = Cpanel::MariaDB::Install->new();
    $obj->install_repo('10.2');

=head1 DESCRIPTION

This object is used to install supported MariaDB releases.

=cut

my $upgrade_hook;

sub upgrade_hook {
    $upgrade_hook //= sprintf(
        Cpanel::PackMan->instance->sys->universal_hooks_post_pkg_pattern,
        'MariaDB-server',
        '100-build_mysql_conf'
    );

    return $upgrade_hook;
}

sub mariadb_packages {
    return Cpanel::OS::mariadb_packages()->@*;
}

sub incompatible_packages {
    return Cpanel::OS::mariadb_incompatible_packages()->@*;
}

#Due to MDEV-22552, mytop is not compatible with MariaDB 10.5
our %incompatible_by_version = (
    10.5 => ['mytop'],
    10.6 => ['mytop'],
);

our @mariadb_remove_before_upgrade = (qw(MariaDB-server));

sub known_mariadb_deps {
    return Cpanel::OS::known_mariadb_deps();
}

sub _get_exclude_packages_for_target_version {
    my ( $self, $version ) = @_;
    return ();
}

sub _get_incompatible_packages {
    my ( $self, $selected_version ) = @_;

    my @incompatible_packages = incompatible_packages();

    if ( defined $selected_version && defined $incompatible_by_version{$selected_version} ) {
        push( @incompatible_packages, @{ $incompatible_by_version{$selected_version} } );
    }
    return \@incompatible_packages;
}

sub _get_known_deps {
    return known_mariadb_deps();
}

sub _get_packages_for_target_version {
    my ( $self, $version ) = @_;

    my @pkgs = mariadb_packages();

    return @pkgs;
}

sub _get_vendor_name {
    return 'MariaDB';
}

sub _get_versions_to_remove {
    return \@mariadb_remove_before_upgrade;
}

sub verify_can_be_installed {
    my ( $self, $target_version ) = @_;
    $self->SUPER::verify_can_be_installed( $target_version, { 'check_yum_preinstall_stderr' => \&_check_yum_preinstall_stderr } );
    return 1;
}

sub _check_yum_preinstall_stderr {
    my ($yum_stderr) = @_;

    return 0 unless defined $yum_stderr;

    # This is the error you get when YUM cannot connect to CentOS servers for various reasons
    # https://wiki.centos.org/yum-errors
    if ( $yum_stderr =~ /\[Errno 14\]/ ) {
        return 1;
    }

    return 0;
}

sub _get_minimum_supported_version {
    return Cpanel::OS::mariadb_minimum_supported_version();
}

1;
