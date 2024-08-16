package Cpanel::OS::Ubuntu22;

# cpanel - Cpanel/OS/Ubuntu22.pm                   Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::OS::Ubuntu';

use constant is_supported => 1;

use constant binary_sync_source         => 'linux-u22-x86_64';
use constant package_release_distro_tag => '~u22';

# TODO: figure out a (good) way to merge with the value inherited from parent
use constant binary_locations => {
    'lsof'            => '/usr/bin',
    'named-checkzone' => '/usr/bin',
    'named-checkconf' => '/usr/bin',
};

use constant maillog_path => '/var/log/mail.log';

# Interestingly, ufw_iptables is in use, but since iptables is just a wrapper
# for nftables when it is installed (and it *is*), firewall_module is NFTables.
use constant firewall_module => 'NFTables';

use constant plugins_repo_url => 'https://securedownloads.cpanel.net/cpanel-plugins/xUbuntu_22.04.list';

use constant supports_imunify_av      => 1;
use constant supports_imunify_av_plus => 1;
use constant supports_imunify_360     => 1;

use constant supports_cpanel_cloud_edition => 1;

use constant ea4_install_bare_repo  => 1;
use constant ea4_from_bare_repo_url => 'https://securedownloads.cpanel.net/EA4/xUbuntu_22.04.list';

use constant cpsc_from_bare_repo_url     => 'http://ea4testing.cpanel.net/CPSC.xUbuntu_22.04.list';
use constant cpsc_from_bare_repo_key_url => 'http://ea4testing.cpanel.net/CPSC/xUbuntu_22.04/Release.key';

# NOTE: This is NOT in Ubuntu.pm because jammy is mentioned here and we don't know how to make it generic ultimately.
use constant mysql_repo_template => <<'___END_REPO_TEMPLATE___';
# Use command 'dpkg-reconfigure mysql-apt-config' as root for modifications.
deb https://repo.mysql.com/apt/ubuntu/ jammy mysql-apt-config
deb https://repo.mysql.com/apt/ubuntu/ jammy mysql-###MYSQL_VERSION_SHORT###
deb https://repo.mysql.com/apt/ubuntu/ jammy mysql-tools
#deb https://repo.mysql.com/apt/ubuntu/ jammy mysql-tools-preview
deb-src https://repo.mysql.com/apt/ubuntu/ jammy mysql-###MYSQL_VERSION_SHORT###
___END_REPO_TEMPLATE___

use constant mariadb_minimum_supported_version => '10.6';

use constant mariadb_repo_template => <<'___END_REPO_TEMPLATE___';
deb [arch=amd64,arm64] https://dlm.mariadb.com/repo/mariadb-server/###MARIADB_VERSION_SHORT###/repo/ubuntu jammy main
deb [arch=amd64,arm64] https://dlm.mariadb.com/repo/mariadb-server/###MARIADB_VERSION_SHORT###/repo/ubuntu jammy main/debug
___END_REPO_TEMPLATE___

use constant stock_kernel_version_regex => qr/-(?:generic|lowlatency|kvm|aws|azure|gcp|gke(?:op)?|ibm|nvidia(?:-lowlatency)?|oracle)$/;
use constant quota_packages_conditional => {

    # Certain kernel metapackages don't include modules for quota support. There is no marking in the packaging system
    # which allows automatically loading these packages when necessary. The name of the auxilliary package is also not
    # completely regular across all metapackages.
    #
    # Those adding "modules-extra":
    'linux-aws'                 => ['linux-modules-extra-aws'],
    'linux-aws-edge'            => ['linux-modules-extra-aws-edge'],
    'linux-aws-lts-22.04'       => ['linux-modules-extra-aws-lts-22.04'],
    'linux-azure'               => ['linux-modules-extra-azure'],
    'linux-azure-edge'          => ['linux-modules-extra-azure-edge'],
    'linux-azure-fde'           => ['linux-modules-extra-azure-fde'],
    'linux-azure-fde-edge'      => ['linux-modules-extra-azure-fde-edge'],
    'linux-azure-fde-5.19-edge' => ['linux-modules-extra-azure-fde-5.19-edge'],
    'linux-azure-fde-lts-22.04' => ['linux-modules-extra-azure-fde-lts-22.04'],
    'linux-azure-lts-22.04'     => ['linux-modules-extra-azure-lts-22.04'],
    'linux-gcp'                 => ['linux-modules-extra-gcp'],
    'linux-gcp-edge'            => ['linux-modules-extra-gcp-edge'],
    'linux-gcp-lts-22.04'       => ['linux-modules-extra-gcp-lts-22.04'],
    'linux-gkeop'               => ['linux-modules-extra-gkeop'],
    'linux-gkeop-5.15'          => ['linux-modules-extra-gkeop-5.15'],

    # Those adding "image-extra":
    'linux-virtual'                => ['linux-image-extra-virtual'],
    'linux-virtual-hwe-22.04'      => ['linux-image-extra-virtual-hwe-22.04'],
    'linux-virtual-hwe-22.04-edge' => ['linux-image-extra-virtual-hwe-22.04-edge'],
};

sub packages_required ($self) {
    my %changes = (
        "libboost-program-options1.71.0" => "libboost-program-options1.74.0",
        "libicu66"                       => "libicu70",
        "libidn11"                       => "libidn12",
        "libpcre2-posix2"                => "libpcre2-posix3",
        "libzip5"                        => "libzip4",                          # no, this is not a typo
    );

    my @packages = map { exists $changes{$_} ? () : $_ } @{ $self->SUPER::packages_required() };
    push @packages, values %changes;
    push @packages, qw(libffi7 sqlite3);                                        # See CPANEL-43410
    return [ sort @packages ];
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Ubuntu22 - Ubuntu 22 custom values

=head1 SYNOPSIS

    # you should not use this package directly
    #   prefer using the abstraction from Cpanel::OS

    use Cpanel::OS ();

=head1 DESCRIPTION

This package represents the supported C<Ubuntu22> distribution.

You should not use it directly. L<Cpanel::OS> provides an interface
to load and use this package if your distribution is C<Ubuntu22>.
