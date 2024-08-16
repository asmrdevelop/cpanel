package Cpanel::Mysql::Install;

# cpanel - Cpanel/Mysql/Install.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PackMan ();
use Cpanel::OS;

use parent "Cpanel::Repo::Install::MysqlBasedDB";

=encoding utf-8

=head1 NAME

Cpanel::Mysql::Install - MySQL installer for "community" packages

=head1 SYNOPSIS

    use Cpanel::Mysql::Install ();

    my $obj = Cpanel::Mysql::Install->new();
    $obj->install_repo('5.7');

=head1 DESCRIPTION

This object is used to install newer (5.7+) MySQL releases.

=cut

my $upgrade_hook;

sub upgrade_hook {
    $upgrade_hook //= sprintf(
        Cpanel::PackMan->instance->sys->universal_hooks_post_pkg_pattern,
        'mysql-community-server',
        '100-build_mysql_conf'
    );

    return $upgrade_hook;
}

our @Mysql_packages = Cpanel::OS::mysql_community_packages()->@*;

# Must be removed for a successful install/update
our @incompatible_packages = Cpanel::OS::mysql_incompatible()->@*;

# If these cannot be installed do not even try to install MySQL
our @mysql_dependencies = Cpanel::OS::mysql_dependencies()->@*;

# The values are the versions, but we currently accept any versions for these
our %known_deps = map { $_ => '' } @mysql_dependencies;

sub _get_exclude_packages_for_target_version {
    return ();
}

sub _get_incompatible_packages {
    return \@incompatible_packages;
}

sub _get_packages_for_target_version {
    return @Mysql_packages;
}

sub _get_vendor_name {
    return 'Mysql';
}

sub _get_known_deps {
    return \%known_deps;
}

sub _repo_id {
    my ( $self, $target_version ) = @_;
    return $self->SUPER::_repo_id($target_version) . '-community';
}

1;
