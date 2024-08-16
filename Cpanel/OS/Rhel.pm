package Cpanel::OS::Rhel;

# cpanel - Cpanel/OS/Rhel.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS::Linux ();    # ea4tooling_all
use parent 'Cpanel::OS::Linux';

use constant is_supported => 0;    # Base OS class for all Rhel derivatives.

use constant pretty_distro => 'Red Hat Enterprise Linux';

use constant sudoers         => 'wheel';
use constant has_wheel_group => 1;

use constant etc_shadow_groups => ['root'];
use constant etc_shadow_perms  => [ 0000, 0200, 0600 ];

use constant dns_supported                     => [qw{ bind powerdns }];
use constant supports_kernelcare               => 1;
use constant supports_kernelcare_free          => 1;
use constant supports_or_can_become_cloudlinux => 1;
use constant can_become_cloudlinux             => 1;
use constant supports_imunify_av               => 1;
use constant supports_imunify_av_plus          => 1;

use constant cron_bin_path                   => '/usr/sbin/crond';
use constant systemd_service_name_map        => {};
use constant firewall                        => 'firewalld_nftables';
use constant firewall_module                 => 'NFTables';
use constant networking                      => 'networkscripts';
use constant package_manager                 => 'dnf';
use constant package_manager_module          => 'Yum';
use constant base_distro                     => 'rhel';
use constant is_apt_based                    => 0;
use constant is_yum_based                    => 1;
use constant is_rpm_based                    => 1;
use constant kernel_package_pattern          => 'kernel';
use constant stock_kernel_version_regex      => qr/\.(?:noarch|x86_64|i[3-6]86)$/;
use constant program_to_apply_kernel_args    => 'grub2-mkconfig';
use constant prelink_config_path             => '/etc/sysconfig/prelink';
use constant pam_file_controlling_crypt_algo => 'system-auth';
use constant user_crontab_dir                => '/var/spool/cron';
use constant who_wins_if_soft_gt_hard        => 'soft';
use constant has_tcp_wrappers                => 0;

# TODO: figure out a (good) way to merge with the value inherited from parent
use constant binary_locations => {
    'lsof'             => '/usr/bin',
    'needs-restarting' => '/usr/bin',
    'named-checkzone'  => '/usr/sbin',
    'named-checkconf'  => '/usr/sbin',
};

use constant cpsc_from_bare_repo_url  => 'http://ea4testing.cpanel.net/CPSC.repo';
use constant cpsc_from_bare_repo_path => '/etc/yum.repos.d/cpsc.repo';

use constant ea4_install_bare_repo   => 1;
use constant ea4_from_bare_repo_url  => 'https://securedownloads.cpanel.net/EA4/EA4.repo';
use constant ea4_from_bare_repo_path => '/etc/yum.repos.d/EA4.repo';

use constant ea4_conflicting_apache_distro_packages => [qw( httpd httpd-tools php-cli )];

# Package dependencies
use constant ea4tooling_dnsonly => ['dnf-plugin-universal-hooks'];
use constant ea4tooling         => [ 'dnf-plugin-universal-hooks', Cpanel::OS::Linux->ea4tooling_all->@* ];

use constant syslog_service_name => 'rsyslogd';

use constant jetbackup_repo_pkg => 'https://repo.jetlicense.com/centOS/jetapps-repo-latest.rpm';

use constant plugins_repo_url => 'https://securedownloads.cpanel.net/cpanel-plugins/0/cpanel-plugins.repo';

use constant repo_suffix => 'repo';
use constant repo_dir    => '/etc/yum.repos.d';

use constant package_repositories => [qw/epel powertools/];

use constant system_exclude_rules => {
    'dovecot'     => 'dovecot*',
    'php'         => 'php*',
    'exim'        => 'exim*',
    'pure-ftpd'   => 'pure-ftpd*',
    'proftpd'     => 'proftpd*',
    'p0f'         => 'p0f',
    'filesystem'  => 'filesystem',
    'kernel'      => 'kernel kernel-xen kernel-smp kernel-pae kernel-PAE kernel-SMP kernel-hugemem kernel-debug* kernel-core kernel-modules*',
    'kmod-'       => 'kmod-[a-z]*',
    'bind-chroot' => 'bind-chroot',
};

use constant packages_supplemental => [

    # for cP Cloud
    'nfs-utils',

    qw{
      ImageMagick
      autoconf
      automake
      bind-devel
      bison
      boost-serialization
      cairo
      e2fsprogs-devel
      expat-devel
      flex
      fontconfig
      freetype
      ftp
      gcc-c++
      gd-devel
      gdbm-devel
      gettext-devel
      ghostscript
      giflib
      glib2
      hunspell
      hunspell-en
      krb5-devel
      libX11-devel
      libXpm
      libXpm-devel
      libaio-devel
      libidn-devel
      libjpeg-turbo-devel
      libpng-devel
      libstdc++-devel
      libtiff-devel
      libtool
      libtool-ltdl
      libtool-ltdl-devel
      libwmf
      libxml2-devel
      libxslt-devel
      ncurses
      ncurses-devel
      nscd
      openssl-devel
      pango
      perl-CPAN
      perl-ExtUtils-MakeMaker
      perl-IO-Tty
      perl-Module-Build
      perl-Try-Tiny
      perl-YAML-Syck
      perl-core
      perl-devel
      perl-libwww-perl
      perl-local-lib
      pixman
      python2-devel
      strace
      sysstat
      traceroute
      urw-fonts
      zlib-devel
    }
];

use constant packages_supplemental_epel => [
    qw{
      dpkg
      perl-Expect
      perl-JSON-XS
    }
];

use constant packages_required => [
    qw{
      aspell
      at
      bind
      bind-libs
      bind-utils
      binutils
      boost-program-options
      bzip2
      cmake-filesystem
      coreutils
      cpio
      cpp
      crontabs
      curl
      dnf
      e2fsprogs
      expat
      file
      gawk
      gcc
      gd
      gdbm
      gettext
      glibc-devel
      glibc-locale-source
      gmp
      gnupg2
      grubby
      gzip
      initscripts
      iptables
      json-c
      kernel-headers
      less
      libaio
      libevent
      libgcc
      libgomp
      libicu
      libidn
      libjpeg-turbo
      libpcap
      libpng
      libstdc++
      libtiff
      libxml2
      libxslt
      libzip
      lsof
      mailx
      make
      nano
      net-tools
      nftables
      openssh
      openssh-clients
      openssh-server
      openssl
      pam
      pam-devel
      passwd
      patch
      pcre
      pcre2
      popt
      python2
      python2-docs
      python2-setuptools
      python2-tools
      python3-dnf
      python3-docs
      python3-libdnf
      python3-setuptools
      python36
      quota
      rsync
      sed
      shadow-utils
      smartmontools
      sqlite
      tar
      unzip
      util-linux-user
      wget
      which
      xz
      yum-utils
      zip
      zlib
    }
];

# OK, so there's an undocumented way to get newer postgresql versions on cPanel here:
# the rh- prefixed packages are only made available by the SCL repos for AlmaLinux,
# but typically contain the more up to date versions of PG.
# Unfortunately with the advent of DNF on AlmaLinux 8, this is not only no longer relevant
# but also causes yum to explode if you ask for both.
# As such, don't ask on AlmaLinux 8, as SCL for newer postgres isn't even a concept there.
use constant postgresql_packages => [
    qw{
      postgresql      postgresql-devel    postgresql-libs     postgresql-server
    }
];

use constant package_ImageMagick_Devel => 'ImageMagick-devel';
use constant package_crond             => 'cronie';

use constant mariadb_versions_use_repo_template => [qw/10.0 10.1 10.2 10.3 10.5 10.6 10.11/];
use constant mysql_versions_use_repo_template   => [qw/5.7 8.0/];

use constant mysql_incompatible => [
    qw{
      mariadb-client
      mariadb-devel
      mariadb-embedded
      mariadb-embedded-devel
      mariadb-libs
      mariadb-libs-compat
      mariadb-release
      mariadb-server
      mariadb-test
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
      mysqlclient16
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
    }
];

use constant mysql_community_packages => [qw/mysql-community-server mysql-community-devel/];

use constant mariadb_packages => [qw( MariaDB-server MariaDB-client MariaDB-devel MariaDB-shared MariaDB-common )];
use constant mariadb_incompatible_packages => [
    qw(
      mariadb-client
      mariadb-devel
      mariadb-embedded
      mariadb-embedded-devel
      mariadb-libs
      mariadb-libs-compat
      mariadb-release
      mariadb-server
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
    'perl-DBI'     => '',
    'shadow-utils' => '',
    'grep'         => '',
    'coreutils'    => '',
};

use constant db_disable_auth_socket => {
    'unix_socket' => 'OFF',
};

use constant db_additional_conf_files     => [];
use constant db_mariadb_default_conf_file => undef;
use constant db_mariadb_start_file        => undef;

use constant mysql_dependencies => [
    qw/
      coreutils
      grep
      perl-DBI
      shadow-utils
      /
];

use constant db_package_manager_key_params => {
    method => 'add_repo_key',
    keys   => [qw{https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 https://repo.mysql.com/RPM-GPG-KEY-MySQL-2022 https://repo.mysql.com/RPM-GPG-KEY-mysql https://archive.mariadb.org/PublicKey https://supplychain.mariadb.com/MariaDB-Server-GPG-KEY}],
};

use constant db_needs_preseed => 0;

use constant mariadb_repo_template => <<'___END_REPO_TEMPLATE___';
[MariaDB###MARIADB_FLAT_VERSION_SHORT###]
name = MariaDB###MARIADB_FLAT_VERSION_SHORT###
baseurl = https://archive.mariadb.org/mariadb-###MARIADB_VERSION_SHORT###/yum/centos/###DISTRO_MAJOR###/x86_64
gpgkey=https://archive.mariadb.org/PublicKey
       https://supplychain.mariadb.com/MariaDB-Server-GPG-KEY
gpgcheck=1
___END_REPO_TEMPLATE___

use constant mysql_repo_template => <<'___END_REPO_TEMPLATE___';
[Mysql-connectors-community]
name=MySQL Connectors Community
baseurl=https://repo.mysql.com/yum/mysql-connectors-community/el/###DISTRO_MAJOR###/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
       https://repo.mysql.com/RPM-GPG-KEY-MySQL-2022
       https://repo.mysql.com/RPM-GPG-KEY-mysql
[Mysql-tools-community]
name=MySQL Tools Community
baseurl=https://repo.mysql.com/yum/mysql-tools-community/el/###DISTRO_MAJOR###/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
       https://repo.mysql.com/RPM-GPG-KEY-MySQL-2022
       https://repo.mysql.com/RPM-GPG-KEY-mysql
[Mysql###MYSQL_FLAT_VERSION_SHORT###-community]
name=MySQL ###MYSQL_VERSION_SHORT### Community Server
baseurl=https://repo.mysql.com/yum/mysql-###MYSQL_VERSION_SHORT###-community/el/###DISTRO_MAJOR###/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
       https://repo.mysql.com/RPM-GPG-KEY-MySQL-2022
       https://repo.mysql.com/RPM-GPG-KEY-mysql
[Mysql-tools-preview]
name=MySQL Tools Preview
baseurl=https://repo.mysql.com/yum/mysql-tools-preview/el/###DISTRO_MAJOR###/$basearch/
enabled=0
gpgcheck=1
gpgkey=https://repo.mysql.com/RPM-GPG-KEY-mysql-2023
       https://repo.mysql.com/RPM-GPG-KEY-MySQL-2022
       https://repo.mysql.com/RPM-GPG-KEY-mysql
___END_REPO_TEMPLATE___

use constant supports_postgresql => 1;

use constant postgresql_minimum_supported_version => '9.2';
use constant postgresql_initdb_commands           => ['/usr/bin/postgresql-setup initdb'];

# Case HB-6392: What package param to use when reading data in Manage Plugins?
use constant package_descriptions => {
    'short' => 'summary',
    'long'  => 'description',
};

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Rhel - Rhel base class

=head1 SYNOPSIS

    use parent 'Cpanel::OS::Rhel';

=head1 DESCRIPTION

This package is an interface for all Rhel distributions.
You should not use it directly.
