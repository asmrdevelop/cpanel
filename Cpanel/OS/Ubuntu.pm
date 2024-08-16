package Cpanel::OS::Ubuntu;

# cpanel - Cpanel/OS/Ubuntu.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS::Linux ();    # ea4tooling_all
use parent 'Cpanel::OS::Linux';
use constant is_supported => 0;

use constant nogroup         => q[nogroup];
use constant sudoers         => 'sudo';       # Warning: need to change dynamicui.conf when updating this value
use constant has_wheel_group => 0;

use constant etc_shadow_groups => [ 'shadow', 'root' ];
use constant etc_shadow_perms => [ 0000, 0200, 0600, 0640 ];

use constant default_sys_uid_min => 100;
use constant default_sys_gid_min => 100;

use constant pretty_distro => 'Ubuntu';

use constant firewall                  => 'ufw_iptables';
use constant firewall_module           => 'IpTables';
use constant networking                => 'netplan';
use constant sysconfig_network         => undef;
use constant package_manager           => 'apt';
use constant package_manager_module    => 'Apt';
use constant is_apt_based              => 1;
use constant is_yum_based              => 0;
use constant is_rpm_based              => 0;
use constant retry_rpm_cmd_no_tty_hack => 0;
use constant base_distro               => 'debian';

use constant supports_cpaddons => 0;

use constant rpm_versions_system => 'ubuntu';
use constant packages_arch       => 'amd64';

use constant db_needs_preseed => 1;

use constant mariadb_versions_use_repo_template => [ '10.5', '10.6', '10.11' ];
use constant mysql_versions_use_repo_template   => ['8.0'];

use constant db_package_manager_key_params => {
    method => 'add_repo_key_by_id',
    keys   => [
        'A8D3785C',    # For MySQL 8.0.36 and up
        '3A79BD29',    # For MySQL 8.0.28 and up
        '5072E1F5',    # For MySQL 8.0.27 and below
                       # See https://dev.mysql.com/doc/refman/8.0/en/checking-gpg-signature.html for more information on MySQL keys.
        'C74CD1D8',    # For all MariaDB versions
                       # See https://mariadb.com/kb/en/gpg/ for more information on MariaDB keys.
    ],
};

use constant who_wins_if_soft_gt_hard => 'hard';

use constant security_service                => 'apparmor';
use constant cron_bin_path                   => '/usr/sbin/cron';
use constant systemd_service_name_map        => { 'crond' => 'cron' };
use constant kernel_package_pattern          => '^linux-image-[0-9]';
use constant check_kernel_version_method     => q[boot-vmlinuz-file];
use constant stock_kernel_version_regex      => qr/-(?:(?:(?:generic|lowlatency)(?:-hwe)?)|kvm|aws|azure|gcp|oracle)$/;
use constant prelink_config_path             => '/etc/default/prelink';
use constant pam_file_controlling_crypt_algo => 'common-password';
use constant user_crontab_dir                => '/var/spool/cron/crontabs';

use constant supports_kernelcare      => 1;
use constant supports_kernelcare_free => 1;
use constant supports_hostaccess      => 1;

# iptables-persistent provides and uses these files
use constant iptables_ipv4_savefile => '/etc/iptables/rules.v4';
use constant iptables_ipv6_savefile => '/etc/iptables/rules.v6';

# Starting in U22, nftables are now used instead of iptables
use constant nftables_config_file => '/etc/nftables.conf';

# package lists.
use constant mysql_incompatible => [
    qw{
      default-mysql-server
      default-mysql-server-core
      mariadb-client
      mariadb-client-10.3
      mariadb-server
      mariadb-server-10.3
      mariadb-test
      mysql-client-8.0
      mysql-server-8.0
      mysql-testsuite
      mysql-testsuite-8.0
    }
];

use constant mysql_community_packages => [qw/mysql-community-server mysql-shell libmysqlclient-dev/];
use constant mysql_dependencies       => [qw/libdbi-perl passwd adduser login coreutils/];

use constant outdated_services_check    => q[needrestart_b];
use constant outdated_processes_check   => q[checkrestart];
use constant check_reboot_method        => q[check-reboot-required];
use constant bin_update_crypto_policies => undef;                      # The update-crypto-policies program is also not supported on Ubuntu.

use constant syslog_service_name         => 'rsyslog';
use constant rsyslog_triggered_by_socket => 1;
use constant ea4_from_bare_repo_path     => '/etc/apt/sources.list.d/EA4.list';

use constant cpsc_from_bare_repo_path => '/etc/apt/sources.list.d/CPSC.list';

use constant ea4_conflicting_apache_distro_packages => [qw( apache2 apache2-utils php-cli )];

use constant ea4tooling_dnsonly => ['apt-plugin-universal-hooks'];
use constant ea4tooling         => [ 'apt-plugin-universal-hooks', Cpanel::OS::Linux->ea4tooling_all->@* ];
use constant system_exclude_rules => {
    'dovecot'    => 'dovecot*',
    'exim'       => 'exim*',
    'filesystem' => 'base-files',                                   # block Ubuntu updates to current installed version (20.04)
    'kernel'     => 'linux-headers* linux-image* linux-modules*',
    'nsd'        => 'nsd',
    'p0f'        => 'p0f',
    'php'        => 'php*',
    'proftpd'    => 'proftpd*',
    'pure-ftpd'  => 'pure-ftpd*',

    #'bind-chroot' => '????' # not sure the ubuntu package to block here
};

use constant packages_supplemental => [

    # for cP Cloud
    'nfs-common',

    qw{
      libcpan-perl-releases-perl
      libexpect-perl
      libio-pty-perl
      libjson-xs-perl
      liblocal-lib-perl
      libmodule-build-perl
      libtry-tiny-perl
      libwww-perl
      libyaml-syck-perl
      lsof
      nscd
      rpm
      strace
      sysstat
      tcpd
      util-linux
    }
];

use constant jetbackup_repo_pkg => 'https://repo.jetlicense.com/ubuntu/jetapps-repo-latest_amd64.deb';

use constant repo_suffix => 'list';
use constant repo_dir    => '/etc/apt/sources.list.d';

use constant packages_required => [
    qw{
      acl
      apt-file
      apt-transport-https
      aspell
      at
      bind9
      bind9-libs
      bind9-utils
      binutils
      bzip2
      coreutils
      cpio
      cpp
      cracklib-runtime
      cron
      curl
      debian-goodies
      debianutils
      e2fsprogs
      expat
      file
      g++
      g++-9
      gawk
      gcc
      gdbmtool
      gettext
      glibc-source
      gnupg2
      graphicsmagick-imagemagick-compat
      gzip
      icu-devtools
      iptables
      iptables-persistent
      language-pack-en-base
      less
      libaio1
      libapt-pkg-perl
      libboost-program-options1.71.0
      libcairo2-dev
      libcrack2
      libdb5.3
      libevent-2.1-7
      libfile-fcntllock-perl
      libfontconfig1-dev
      libgcc1
      libgd-tools
      libgd3
      libgmp10
      libgomp1
      libicu-dev
      libicu66
      libidn11
      libjpeg-turbo8
      liblua5.3-dev
      libmount1
      libmysqlclient21
      libncurses5
      libpam0g
      libpam0g-dev
      libpango-1.0-0
      libpangocairo-1.0-0
      libpcap0.8
      libpcre2-8-0
      libpcre2-posix2
      libpcre3
      libpixman-1-0
      libpng16-16
      libpopt0
      libreadline-dev
      libssl-dev
      libstdc++-9-dev
      libstdc++6
      libtiff5
      libuser
      libxml2
      libxml2-dev
      libxslt1.1
      libzip5
      linux-libc-dev
      lsof
      make
      nano
      needrestart
      net-tools
      openssh-client
      openssh-server
      openssl
      passwd
      patch
      pcre2-utils
      procps
      python-setuptools
      python2
      python2-doc
      python2.7-dev
      quota
      rdate
      rsync
      sed
      smartmontools
      ssl-cert
      sysstat
      tar
      unzip
      usrmerge
      wget
      xz-utils
      zip
      zlib1g
    }
];

use constant mariadb_packages => [qw( mariadb-server mariadb-client mariadb-common )];
use constant mariadb_incompatible_packages => [
    qw(
      mariadb-devel
      mariadb-embedded
      mariadb-embedded-devel
      mariadb-libs
      mariadb-libs-compat
      mariadb-release
      mariadb-test
      mysql-community-client
      mysql-community-common
      mysql-community-devel
      mysql-community-embedded
      mysql-community-embedded-devel
      mysql-community-libs
      mysql-community-libs-compat
      mysql-community-release
      mysql-community-server
      mysql-community-test
      mysql-client
      mysql-devel
      mysql-embedded
      mysql-embedded-devel
      mysql-libs
      mysql-libs-compat
      mysql-release
      mysql-server
      mysql-test
      mysql55-mysql-bench
      mysql55-mysql-devel
      mysql55-mysql-libs
      mysql55-mysql-server
      mysql55-mysql-test
      mysql57-community-release
      mysql80-community-release
      rh-mysql56-mysql-bench
      rh-mysql56-mysql-common
      rh-mysql56-mysql-config
      rh-mysql56-mysql-devel
      rh-mysql56-mysql-errmsg
      rh-mysql56-mysql-server
      rh-mysql56-mysql-test
      rh-mysql57-mysql-common
      rh-mysql57-mysql-config
      rh-mysql57-mysql-devel
      rh-mysql57-mysql-errmsg
      rh-mysql57-mysql-server
      rh-mysql57-mysql-test
    )
];

use constant known_mariadb_deps => {
    'libdbi-perl'      => '',
    'libvshadow-utils' => '',
    'grep'             => '',
    'coreutils'        => '',
};

use constant db_disable_auth_socket => {
    'unix_socket'     => 'OFF',
    'plugin-load-add' => 'auth_socket.so'
};

use constant db_additional_conf_files     => [ '/etc/mysql/debian.cnf', '/etc/mysql/mariadb.cnf' ];
use constant db_mariadb_default_conf_file => '/etc/mysql/mariadb.cnf';
use constant db_mariadb_start_file        => '/etc/mysql/debian-start';

use constant package_ImageMagick_Devel => 'libmagick++-6.q16-dev';
use constant package_crond             => 'cron';

use constant system_package_providing_perl => 'perl-base';

use constant bin_grub_mkconfig            => q[/usr/sbin/grub-mkconfig];
use constant program_to_apply_kernel_args => 'grub-mkconfig';

# Case HB-6392: What package param to use when reading data in Manage Plugins?
use constant package_descriptions => {
    'short' => 'description',
    'long'  => 'longdesc',
};

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Ubuntu - Ubuntu base class

=head1 SYNOPSIS

    use parent 'Cpanel::OS::Ubuntu';

=head1 DESCRIPTION

This package is an interface for all Ubuntu distributions.
You should not use it directly.
