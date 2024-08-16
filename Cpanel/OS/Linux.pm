package Cpanel::OS::Linux;

# cpanel - Cpanel/OS/Linux.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Carp ();

use Cpanel::OS ();
use parent -norequire, 'Cpanel::OS';

use constant eol_advice                      => '';
use constant is_supported                    => 0;        # Base OS class for all platforms we currently support.
use constant support_needs_minor_at_least_at => undef;    # by default no restriction on minor version

use constant is_experimental  => 0;                       # By default, no distros are experimental.
use constant experimental_url => '';                      # ... and so no URL to document it.

use constant dns_supported                 => [qw{ powerdns }];    # All platforms support powerdns as it is our default.
use constant supports_3rdparty_wpt         => 1;                   # We support WPT on all platforms ATM.
use constant supports_plugins_repo         => 1;
use constant supports_imunify_av           => 0;
use constant supports_imunify_av_plus      => 0;
use constant supports_imunify_360          => 0;
use constant supports_letsencrypt_v2       => 1;
use constant supports_cpanel_analytics     => 1;
use constant supports_cpanel_cloud_edition => 0;
use constant cpsc_from_bare_repo_url       => undef;
use constant cpsc_from_bare_repo_path      => undef;
use constant cpsc_from_bare_repo_key_url   => undef;

use constant can_elevate_to => [];

use constant setup_tz_method => q[timedatectl];

use constant nobody  => q[nobody];
use constant nogroup => q[nobody];

use constant default_uid_min     => 1_000;
use constant default_gid_min     => 1_000;
use constant default_sys_uid_min => 201;
use constant default_sys_gid_min => 201;

use constant dns_named_basedir => '/var/named';
use constant dns_named_conf    => '/etc/named.conf';
use constant dns_named_log     => '/var/log/named';
use constant service_manager   => 'systemd';
use constant arch              => 'x86_64';
use constant maillog_path      => '/var/log/maillog';

use constant supports_hostaccess => 0;

use constant rsyslog_triggered_by_socket => 0;

use constant packages_supplemental_epel => [];
use constant quota_packages_conditional => {};

use constant unsupported_db_versions => [];
use constant mariadb_repo_template   => '';    # Not provided on ubuntu for instance.

use constant mariadb_minimum_supported_version    => '10.3';
use constant mysql_default_version                => '8.0';
use constant postgresql_minimum_supported_version => undef;
use constant postgresql_packages                  => [];
use constant postgresql_service_aliases           => [];
use constant postgresql_initdb_commands           => [];
use constant openssl_minimum_supported_version    => '1.0.2e';

use constant ea4_install_repo_from_package => 0;
use constant ea4_from_pkg_url              => undef;
use constant ea4_from_pkg_reponame         => undef;
use constant ea4_install_bare_repo         => 0;
use constant ea4_from_bare_repo_url        => undef;
use constant ea4_from_bare_repo_path       => undef;
use constant ea4_modern_openssl            => '/usr/bin/openssl';

use constant ea4tooling_all => [qw{ ea-cpanel-tools ea-profiles-cpanel }];

sub ea4tooling_dnsonly   { return Carp::confess('ea4tooling_dnsonly unimplemented for this distro') }
sub ea4tooling           { return Carp::confess('ea4tooling unimplemented for this distro') }
sub system_exclude_rules { return Carp::confess('system_exclude_rules unimplemented for this distro') }
sub base_distro          { return Carp::confess('base_distro unimplemented for this distro') }

sub kernel_package_pattern { return Carp::confess('unimplemented for this distro') }
use constant check_kernel_version_method => q[grubby];
use constant stock_kernel_version_regex  => undef;

sub mysql_versions_use_repo_template   { return Carp::confess('unimplemented for this distro') }
sub mariadb_versions_use_repo_template { return Carp::confess('unimplemented for this distro') }

sub binary_sync_source { return Carp::confess('unimplemented for this distro') }

use constant package_repositories => [];

use constant system_package_providing_perl => 'perl';

use constant rpm_versions_system => 'centos';    # This has to do with where we publish rpms. Do not change or remove it.
use constant packages_arch       => 'x86_64';

use constant package_MySQL_Shell => q[mysql-shell];
use constant package_crond       => undef;

use constant retry_rpm_cmd_no_tty_hack => 1;

use constant check_ntpd_pid_method => 'pid_check_var_run_ntpd';    # how to check ntp daemon pid

use constant prelink_config_path => undef;

use constant pam_file_controlling_crypt_algo => undef;

use constant rsync_old_args => [];

#
use constant iptables_ipv4_savefile => '/etc/sysconfig/iptables';
use constant iptables_ipv6_savefile => '/etc/sysconfig/ip6tables';
use constant nftables_config_file   => '/etc/sysconfig/nftables.conf';
use constant sysconfig_network      => q[/etc/sysconfig/network];

# bin path
use constant bin_grub_mkconfig          => q[/usr/sbin/grub2-mkconfig];
use constant bin_update_crypto_policies => q[/usr/bin/update-crypto-policies];

# ssh
use constant ssh_supported_algorithms => [qw{ ed25519 ecdsa rsa }];

# binaries
use constant binary_locations => {
    'lsof' => '/usr/bin',
};

use constant outdated_services_check  => q[default];
use constant outdated_processes_check => q[default];
use constant check_reboot_method      => q[default];

use constant program_to_apply_kernel_args => undef;

use constant security_service => 'selinux';

# Default NO
use constant supports_kernelcare                       => 0;
use constant supports_kernelcare_free                  => 0;
use constant supports_or_can_become_cloudlinux         => 0;
use constant can_become_cloudlinux                     => 0;
use constant supports_inetd                            => 0;
use constant supports_syslogd                          => 0;
use constant supports_postgresql                       => 0;
use constant has_cloudlinux_enhanced_quotas            => 0;
use constant ea4_install_from_profile_enforce_packages => 0;
use constant is_cloudlinux                             => 0;
use constant can_be_elevated                           => 0;
use constant crypto_policy_needs_sha1                  => 0;

# As of AlmaLinux 8.0.1905 (dnf 4.0.9 and libdnf 0.22.5)
#     there is no method provided to clean the fastestmirror cache
#       so this must be skipped for now.
use constant can_clean_plugins_repo => 0;

# Default YES
use constant has_quota_support_for_xfs            => 1;
use constant is_systemd                           => 1;
use constant has_tcp_wrappers                     => 1;
use constant supports_cpaddons                    => 1;
use constant openssl_escapes_subjects             => 1;
use constant kernel_supports_fs_protected_regular => 1;

use constant pretty_distro => undef;

sub display_name {
    return sprintf( "%s v%s.%s.%s", Cpanel::OS::pretty_distro() // '', Cpanel::OS::major() // '', Cpanel::OS::minor() // '', Cpanel::OS::build() // '' );    ## no critic(Cpanel::CpanelOS) internal usage
}

sub display_name_lite {
    return sprintf( "%s %s", lc( Cpanel::OS::distro() // '' ), Cpanel::OS::major() // '' );                                                                  ## no critic(Cpanel::CpanelOS) internal usage
}

# CPANEL-37918: This needs to be formatted this way to match data in an existing Google Analytics database.
sub cpanalytics_cpos {
    return sprintf( "%s %s.%s", uc( Cpanel::OS::distro() // '' ), Cpanel::OS::major() // '', Cpanel::OS::minor() // '' );                                    ## no critic(Cpanel::CpanelOS) internal usage
}

use constant var_named_permissions => {
    'mode'      => 0755,
    'ownership' => [ 'named', 'named' ],
};

# Testing
use constant nat_server_buffer_connections => 2;

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS::Linux - Linux base class

=head1 SYNOPSIS

    use parent 'Cpanel::OS::Linux';

=head1 DESCRIPTION

This package is an interface for all Linux based distributions.
This is currently the main parent of all supported distributions.
You should not use this package directly.
