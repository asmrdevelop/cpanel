package Cpanel::OS;

# cpanel - Cpanel/OS.pm                            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Carp                         ();
use Cpanel::OS::SysPerlBootstrap ();
use Cpanel::LoadModule           ();

our $VERSION = '2.0';

# Do not call this directly. It's mostly used for testing.
sub _new_instance ( $os, $distro, $major, $minor, $build ) {
    my $distro_class = 'Cpanel::OS::' . ucfirst($distro) . $major;

    my $fallback_to_linux;
    if ( $INC{'Cpanel/OS/All.pm'} ) {

        # never try to load other distro package when OS::All is loaded.
        $fallback_to_linux = 1 unless $distro_class->can('is_supported');
    }
    else {
        $fallback_to_linux = 1 unless eval "require $distro_class; 1";    ## no critic qw(ProhibitStringyEval) -- This is how we do a runtime load here.
    }

    if ($fallback_to_linux) {
        require Cpanel::OS::Linux;                                        # PPI USE OK -- used just after
        $distro_class = q[Cpanel::OS::Linux];                             # unsupported distro

        $os //= q[Unknown];
    }

    # bless as the appropriate class.
    my $self = bless {
        os     => $os,
        distro => $distro,
        major  => $major,
        minor  => $minor,
        build  => $build,
    }, $distro_class;

    return $self;
}

my $instance;

sub clear_cache {
    $INC{'Test/Cpanel/Policy.pm'} or Carp::croak("This interface is only for unit testing");
    undef $instance;

    return;
}

# only valid case for now to clear the cache
sub clear_cache_after_cloudlinux_update {
    undef $instance;
    return;
}

sub _instance {    ## no critic(RequireArgUnpacking) - Most of the time we do not need to process args.
    return $instance if $instance;

    Carp::croak("Cpanel::OS may not be called during cPanel binary compilation") if $INC{'B/C.pm'};

    my ( $os, $distro, $major, $minor, $build ) = @_;
    if ( !length $build ) {
        ( $os, $distro, $major, $minor, $build ) = Cpanel::OS::SysPerlBootstrap::get_os_info('DO NOT USE THIS CALL');
    }

    return $instance = _new_instance( $os, $distro, $major, $minor, $build );
}

sub flush_disk_caches {
    local $!;

    # Don't bust cache if the custom file is present and has a "true" symlink.
    return 0 if readlink Cpanel::OS::SysPerlBootstrap::CACHE_FILE_CUSTOM;
    unlink Cpanel::OS::SysPerlBootstrap::CACHE_FILE;

    return 1;
}

# Basic 'get' accessors
sub distro { return _instance()->{'distro'} }
sub major  { return _instance()->{'major'} }
sub minor  { return _instance()->{'minor'} }
sub build  { return _instance()->{'build'} }

## NOTE: private methods (beginning with _) are NOT allowed in this list!
my %methods;

BEGIN {

    # The key specifies what the method that all platforms we support.
    # The value specifies how many args the method is designed to take.
    %methods = map { $_ => 0 } (
        ### General distro specific methods.
        'is_supported',                       # This OS is supported by cPanel and not a virtual class (these exist!).
        'eol_advice',                         # Additional information provided to updatenow blockers when the customer tries to upgrade on a removed distro.
        'support_needs_minor_at_least_at',    # miniimum minor version we support for this distro (optional
        'is_experimental',                    # Defines if this distro is in experimental state or not.
        'experimental_url',                   # Provides a link to information about the experimental state if it's currently that way.
        'arch',                               # Somewhat of an unnecessary variable as all of our distros are set to x86_64.
        'service_manager',                    # Does this distro use systemd or initd to manage services?
        'is_systemd',                         # Easy boolean helper we use in most places to determine if the local system uses systemd.
        'base_distro',                        # What is the root distro this distro is derived from? rhel/debian
        'pretty_distro',                      # What is the preferred stylization of the distro name when being displayed for a user?
        'display_name',                       # Example: Centos v7.9.2009
        'display_name_lite',                  # Example: centos 7
        'cpanalytics_cpos',                   # How should we present data regarding the OS to Google Analytics?
        'binary_sync_source',                 # Provides the string corresponding to the binary sync source directory.

        'nobody',                             # name of the user used for nobody
        'nogroup',                            # name of the group used for nobody / nogroup

        'etc_shadow_groups',                  # group name that owns /etc/shadow
        'etc_shadow_perms',                   # expected permissions for /etc/shadow

        'sudoers',                            # name of the group used for sudo (by sudoers)
        'has_wheel_group',                    # flag for whether wheel group is needed by sudo

        'default_uid_min',                    # default value from /etc/login.defs
        'default_gid_min',                    # default value from /etc/login.defs
        'default_sys_uid_min',                # default value from /etc/login.defs
        'default_sys_gid_min',                # default value from /etc/login.defs

        'has_tcp_wrappers',                   # The distro supports TPC wrappers.

        'setup_tz_method',                    # what method to use to setup a timezone
        'is_cloudlinux',                      # is it a CloudLinux based distro? boolean

        'can_be_elevated',                    # ELevate supports current OS as a source
        'can_elevate_to',                     # ELevate can directly convert the current OS to these other OSes listed in the arrayref

        'rsyslog_triggered_by_socket',        # Is rsyslog triggered by syslog.socket

        ### Misc
        'rsync_old_args',                     # If needed, the args to make rsync behave as it did prior to CVE-2022-29154
        'crypto_policy_needs_sha1',           # This distro/version needs to have SHA1 added to its crypto policies

        ### Quota
        'has_quota_support_for_xfs',          # Does this distro support xfs quota?
        'program_to_apply_kernel_args',       # What program do we need to run to ensure that kernels are booted with updated args?
        'has_cloudlinux_enhanced_quotas',     # Cloud linux does fancy things with quota we need to know about.
        'who_wins_if_soft_gt_hard',           # If we try to set a soft quota higher than a hard quota, which value wins?
        'quota_packages_conditional',         # Hashref of needed kernel package dependencies not encoded in the upstream distro in order for quotas to work

        ### bin
        'bin_grub_mkconfig',                  # path to sbin/grub2-mkconfig
        'bin_update_crypto_policies',         # path to update-crypto-policies binary

        ### binaries path
        'binary_locations',                   # paths to Cpanel::Binaries entries for this distro

        'outdated_services_check',            # which method to use to check outdated services?
        'outdated_processes_check',           # which method to use to check outdated processes?
        'check_reboot_method',                # which method to use to check if we need to reboot

        ### DNS Subsystem variables.
        'dns_supported',                      # Provides a list of dns servers supported on this platform.
        'dns_named_basedir',                  # The path to the bind nameserver files.
        'dns_named_conf',                     # /etc/named.conf
        'dns_named_log',                      # What dir named logs are stored (/var/log/named)
        'var_named_permissions',              # Permissions data for /var/named

        ### SSH
        'ssh_supported_algorithms',           # list of supported ssh algo [ordered by preference]

        'openssl_minimum_supported_version',  # minimum openssl version to run
        'openssl_escapes_subjects',           # On generated certs, openssl started escaping subject lines at some point...

        ### FTP services

        ### SQL database servers
        'unsupported_db_versions',                 # What DB versions does this distro NOT support.
        'db_package_manager_key_params',           # Hashref describing what to do to ensure keys are in place for DBMSes installed from a 3rdparty repo
        'db_disable_auth_socket',                  # Hashref of values needed to disable auth_socket for databases.
        'db_needs_preseed',                        # Does the DB need to do a preseed on install?
        'db_additional_conf_files',                # Any conf files that need to be symlinked.
        'db_mariadb_default_conf_file',            # The default conf file for mariadb, only set if it is not /etc/my.cnf
        'db_mariadb_start_file',                   # The startup script used by systemd for mariadb
        'mysql_versions_use_repo_template',        # Which MySQL versions use mysql_repo_template.
        'mariadb_versions_use_repo_template',      # Which MariaDB versions use mariadb_repo_template.
        'mysql_repo_template',                     # What goes in the repo file to download mysql packages.
        'mariadb_repo_template',                   # What goes in the repo file to download mariadb packages.
        'mariadb_minimum_supported_version',       # Minimum version of MariaDB supported
        'mariadb_packages',                        # List of packages needed to install MariaDB.
        'known_mariadb_deps',                      # List of dependencies needed for MariaDB installation.
        'mariadb_incompatible_packages',           # List of packages that are not compatible with MariaDB.
        'mysql_community_packages',                # Which MySQL packages need to be installed on this distro?
        'mysql_dependencies',                      # Which distro packages need to be installed for MySQL to be happy?
        'mysql_incompatible',                      # Which mysql packages need to be blocked as incompatible with cPanel packages on this distro?
        'mysql_default_version',                   # Default MySQL version to use
        'supports_postgresql',                     # Do we support PostgreSQL on this distro?
        'postgresql_minimum_supported_version',    # What is the minimum versions of PostgreSQL supported on this distro?
        'postgresql_packages',                     # What packages do we need to install?
        'postgresql_service_aliases',              # What aliases, if any, of the service name might we expect to find PostgreSQL using?
        'postgresql_initdb_commands',              # Which commands do we run to make PostgreSQL initialize its DB storage area?

        ### HTTP
        'cpsc_from_bare_repo_url',                   # Where can we download the repo file from? (needs to be over https)
        'cpsc_from_bare_repo_path',                  # ... And where should we put it when we download it?
        'cpsc_from_bare_repo_key_url',
        'ea4_install_repo_from_package',             # Does an RPM provide an EA4 repo?
        'ea4_from_pkg_url',                          # If we're installing the repo from RPM, where do we get it from?
        'ea4_from_pkg_reponame',                     # ... And what will the repo be called when we install it?
        'ea4_install_bare_repo',                     # Do we download a bare repo file?
        'ea4_from_bare_repo_url',                    # Where can we download the repo file from? (needs to be over https)
        'ea4_from_bare_repo_path',                   # ... And where should we put it when we download it?
        'ea4tooling_all',                            # LIST - What are the packages to install which provide ea4 tooling on all server types?
        'ea4tooling',                                # LIST - What ea4 tooling packages do we install on full cpanel servers?
        'ea4tooling_dnsonly',                        # LIST - What additional packages do we need for dnsonly? << FACT CHECK
        'ea4_modern_openssl',                        # Which openssl should be used on this platform to get the L&G Stuff? EA4 provides one in the event the distro's version is insufficient.
        'ea4_conflicting_apache_distro_packages',    # Conflicting packages that Cpanel::EA4::MigrateBlocker checks for
        'ea4_install_from_profile_enforce_packages',

        ### Packaging
        'package_manager',                           # which package manager does the distro use? ( yum/dnf/apt)
        'package_manager_module',                    # Cpanel::whatever::$package_manager_module::... ( Yum or Apt )
        'package_repositories',                      # what additional repos need to be installed and enabled to install needed software?
        'package_release_distro_tag',                # the postfix extension used for the packages: ~el6, ~el7, ~el8, ~el9, ~u20, ~u22
        'system_exclude_rules',                      # On yum based systems, how what will we block the main distro from installing
        'kernel_package_pattern',                    # What are the kernal packages named so we can sometimes block them when updating.
        'check_kernel_version_method',               # What method to use to check the kernel version
        'stock_kernel_version_regex',                # Regular expression used to determine whether the version string returned for the kernel matches what the distro would return with a stock kernel.
        'kernel_supports_fs_protected_regular',      # Does fs.protected_regular a valid settings
        'packages_required',                         # Which packages should /scripts/sysup assure are present on this system? ( provided during fresh install )
        'packages_supplemental',                     # Which packages should /scripts/sysup assure are present on this system? ( provided AFTER fresh install )
        'packages_supplemental_epel',                # Packages we want to install from epel if it is available to us.
        'is_apt_based',                              # Does this system use apt (and therefore deb packages) for package management?
        'is_yum_based',                              # Does this system use a yum or a yum derivative (dnf)
        'is_rpm_based',                              # Does this system do its package management with rpms?
        'system_package_providing_perl',             # Name of the package providing system Perl
        'retry_rpm_cmd_no_tty_hack',                 # Hack: retry RPM comand when no TTY
        'can_clean_plugins_repo',                    # Can we clean the 'plugins' repo
        'rpm_versions_system',                       # Which rpm_versions_system is currently used
        'packages_arch',                             # Default architecture used by the rpm.versions system
        'package_ImageMagick_Devel',                 # Name of the imagemagick devel package
        'package_MySQL_Shell',                       # Name of the mysql-shell package (installed on demand)
        'package_crond',                             # Name of the package providing the cron daemon
        'plugins_repo_url',                          # URL to .repo / .list for cpanel-plugins
        'repo_suffix',                               # Suffix for repo files, such as .repo or .list
        'repo_dir',                                  # Local directory path where system repo config files are stored for the package manager
        'package_descriptions',                      # Description fields used in manage plugins

        ### cPCloud
        'supports_cpanel_cloud_edition',             # Is cPCloud supported by this distro?

        ### 3rd party stuff that doesn't ship with cPanel
        'supports_cpaddons',                         # Are cpaddons supported by this distro?
        'supports_kernelcare',                       # Is Kernel Care available for this distro?
        'supports_kernelcare_free',                  # Is Kernel Care Free available for this distro? << FACT CHECK (Note: This check implicitly ensures the system is not running CloudLinux)
        'supports_3rdparty_wpt',                     # Is WP Toolkit supported on this platform?
        'supports_plugins_repo',                     # Is Cpanel::Plugins::Repo supported on this platform?
        'supports_or_can_become_cloudlinux',         # Does the system can become/or is CloudLinux?
        'can_become_cloudlinux',                     # Can the system become CloudLinux?
        'supports_imunify_av',                       # Can install Imunify AV
        'supports_imunify_av_plus',                  # Can install Imunify AV Plus
        'supports_imunify_360',                      # Can install Imunify AV 360
        'jetbackup_repo_pkg',                        # URL to the package we install to set up the JetBackup repo ( somewhere on http://repo.jetlicense.com/ )
        'supports_letsencrypt_v2',
        'supports_cpanel_analytics',

        ### Local system behaviors
        'security_service',                          # What security service the distro is using? apparmor or selinux

        ### network & firewall
        'firewall',                                  # Which firewall is this distro using? (iptables / firewalld_nftables / ufw_iptables)
        'firewall_module',                           # Which firewall module is used to manage it? (IpTables / NFTables)
        'networking',                                # Not sure what this is for. Nothing uses it. ( networkscripts / netplan ) << FACT CHECK
        'iptables_ipv4_savefile',                    # Where to store iptables rules for IPv4
        'iptables_ipv6_savefile',                    # Where to store iptables rules for IPv6
        'nftables_config_file',                      # Where does nftables.conf live
        'sysconfig_network',                         # sysconfig networ file to use, undef when unused.
        'supports_hostaccess',                       # Does the system provide support for /etc/hosts.allow, etc.?
        'supports_inetd',                            # Does the system provide support for inetd?
        'supports_syslogd',                          # Does the system provide support for syslogd?
        'check_ntpd_pid_method',                     # Method used to check the ntp daemon pid
        'syslog_service_name',                       # Name of the service that handles syslog data, such as syslog, rsyslog, rsyslogd, etc, eg: `/usr/bin/systemctl show -p MainPID rsyslog.service`
        'cron_bin_path',                             # Path to the cron daemon
        'systemd_service_name_map',                  # Map of service names to possible counterparts, such as crond -> cron
        'prelink_config_path',                       # Where do the control knobs for prelinking live?
        'pam_file_controlling_crypt_algo',           # Which file in /etc/pam.d manages the algorithm used to generate the passwd hash written to /etc/shadow for a user?
        'user_crontab_dir',                          # Path to directory where user crontabs are stored by the crontab binary

        ### File paths that can differ by distro
        'maillog_path',                              # Path to the mail.* syslog output as defined by the distro

        ### Testing
        'nat_server_buffer_connections',             # Number of connections_required to trigger a test failure in simultaneous connections for NAT detection.
    );
}

sub supported_methods {
    return sort keys %methods;                       ##no critic qw( ProhibitReturnSort ) - this will always be a list.
}

our $AUTOLOAD;                                       # keep 'use strict' happy

sub AUTOLOAD {    ## no critic(RequireArgUnpacking) - Most of the time we do not need to process args.
    my $sub = $AUTOLOAD;
    $sub =~ s/.*:://;

    exists $methods{$sub} or Carp::croak("$sub is not a supported data variable for Cpanel::OS");

    my $i   = _instance();
    my $can = $i->can($sub) or Carp::croak( ref($i) . " does not implement $sub" );
    return $can->( $i, @_ );
}

sub list_contains_value ( $key, $value ) {
    my $array_ref = _instance()->$key;
    ref $array_ref eq 'ARRAY' or Carp::croak("$key is not a list!");
    if ( !defined $value ) {
        return ( grep { !defined $_ } @$array_ref ) ? 1 : 0;
    }
    return ( grep { $value eq $_ } @$array_ref ) ? 1 : 0;
}

sub DESTROY { }    # This is a must for autoload modules.

#################
#### non-logic ##
#################

# This function is also intended to be temporary, in order to more forcefully
# help assure during smoking that a particular code path is not used under
# Ubuntu.
sub assert_unreachable_on_ubuntu ( $msg = "Ubuntu reached somewhere it shouldn't!" ) {
    Carp::croak($msg) if Cpanel::OS::base_distro() eq "debian";
    return;
}

sub lookup_pretty_distro ($target) {

    # XXX The idea was to use $target to load "Cpanel::OS::$target" and call everything directly against that.
    #     This doesn't work completely because major() is special. pretty_distro() method works, though.

    require Cpanel::OS::All;

    my ( $name, $major ) = ( $target =~ m/^([A-Za-z]+)([0-9]+)$/ );
    return if !$name || !$major;
    return unless grep { $_->[0] eq $name && $_->[1] == $major } Cpanel::OS::All::supported_distros();

    my $module = "Cpanel::OS::$target";
    Cpanel::LoadModule::load_perl_module($module);

    my $pretty_name = $module->pretty_distro;
    return "$pretty_name $major";
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::OS - Abstract interface to the OS to obviate the need for if-this-os-do-this-elsif-elsif-else tech debt

=head1 SYNOPSIS

    my $pm = Cpanel::PackMan->instance;
    $pm->sys->install( Cpanel::OS::packages_required()->@* );

as opposed to crufty tech debt version we’ve come to know and not-love:

    if ($x eq "centos" && $y < 7) {
        @packages = …;
    }
    elsif ($x eq "cloudlinux" && $y > 6) {
        @packages = …;
    }
    elsif (…
        …

    $x eq "ubuntu" ? call_apt_to_install(@packages) : $y < 8 ? call_yum(@packages) : call_dnf(@packages);

=head1 DESCRIPTION

The goal is to make an abstract interface to OS-specific things so our code can be as OS agnostic as possible. In other words, there should be very few places normal code should be doing things based on the OS information. Such places should contain an explanation justifying why it must be done that way.

=head1 DESIGN

=head2 Problem Space

It was historically very difficult to add support in cPanel for a new OS. The reason why is because OS variations are handled by logic checking the os name and version to determine what the thing in question needs. That is undesirable for a number of reasons, including, but not limited to:

=over

=item * We have to update hundreds if not thousands of places arbitrarily strewn through our code base.

=item * As we learn we need to make another adjustment, we repeat the mass find and edit.

=item * It adds more complexity that needs to be tested and documented.

=back

These problems are expensive to address, result in bad UX, and limit us due to ever-increasing tech debt.

=head2 Overall Approach

Instead of peppering the implementation with conditionals asking about OS names and numbers needed to figure out what to do depending on the OS, have the code ask L<Cpanel::OS> for the answer to the actual question. We are rarely interested in the distro and version numbers themselves; instead, we are interested in finding the information we need, information that can change between OSes.

L<Cpanel::OS> aims to let code ask the question we’re really asking — "Hey, what foo should I use?" — without needing to understand anything about the OS.

For example, take this simple need:

   sub get_foo {
       my $foo;
       if ($dist eq "centos" && $major > 6) {
           $foo = "x";
       }
       elsif ($dist eq "centos" && $major < 6) {
           $foo = "y";
       }

       return $foo;
   }

   …

   my $foo = get_foo();
   process_foo($foo);

In case you are unconvinced, this code has several problems:

=over

=item 1. It does not set $foo for CentOS/CloudLinux 6.

=item 2. It does not differentiate between CloudLinux and CentOS.

=item 3. It needs more code to add a new OS, e.g. Ubuntu.

=item 4. We have to find this code when adding a new OS.

=item 5. It can be undefined, leading to unexpected result.

=item 6. It contains logic for unsupported OSs.

=item 7. Ever more complex docs and tests need to be updated as C<get_foo()> changes.

=back

Now take the L<Cpanel::OS> version:

    my $foo = Cpanel::OS::foo();
    process_foo($foo);

All are non-issues now, from the perspective of the wider code base.

Some of the benefits:

=over

=item * A new OS can be added by defining its data in a few boilerplate code files.

=item * It results in far less code to write, test, and document.

=item * As we switch code to support Ubuntu, we can remove systems that support the undesireable approach, for example, L<Cpanel::GenSysInfo> and similar. Less code and more consistency.

=back

=head2 Goals/Requirements

=head3 Make it easy to define an OS in git.

This allows us to add and edit OSes without many code changes.

=head3 Make it possible to provide fix-ups for specific OS releases.

Implementations of individual properties can be made to vary in order to address OS changes introduced between minor releases of the same major version of a distro. See L</HOWTO> for more details.

=head3 Easy to use.

Use systems with as low a level as possible.

Rely on a minimum of dependencies.

=head2 DDaS Videos

=over

=item 1. Think Inside the Box - OS Abstraction Part 1: The Why

L<https://fileshare.cpanel.net/index.php/s/m9xxBdotGRsyZiw>

=item 2. Be 😎Some — OS Abstraction Part 2: The How

L<https://cpanel.wiki/download/attachments/164465475/2021-04-19%20-%20DDaS.mp4>

=back

=head1 FUNCTIONS

=head2 Properties

=head3 os()

Returns the os. Same as C<$^O>.

=head3 distro()

Returns the distro name.

=head3 major()

Returns the major version number.

=head3 minor()

Returns the minor version number.

=head3 build()

Returns the build part of the version number.

=head3 Refer to code comments for other properties

Unfortunately, POD is not conducive to keeping the code readable for the rest of the properties. See %Cpanel::OS::methods for a complete list and some description.

=head2 Utility functions

=head3 list_contains_value($property => $check_value)

Returns 1 if the arrayref corresponding to $property contains the value $check_value; returns 0 if it does not contain the value. Dies if $property is not an arrayref.

=head1 HOWTO

=over

=item How do I add a new property?

=over

=item * Add the property name to the list of %methods in L<Cpanel::OS>.

=item * Determine the most appropriate submodules and add the property and its values there with C<use constant> or C<sub>.

=item * Check for coverage and correctness using C<ot value>.

=back

=item How do I add a new distro or version of a distro?

If a new distro is sufficiently unrelated to any existing distro, create a virtual class inheriting from L<Cpanel::OS::Linux> bearing the name of the distro, then create a class with the major version appended to the distro name which inherits from that virtual class. Ensure that the C<supported> property is set to false for the virtual class, and set other properties appropriately. Add the new distro version to L<Cpanel::OS::All>. Classes representing future versions of such a distro should inherit from the previous version. The example for this is Ubuntu (though if we started supporting Debian proper, this would no longer be a valid example of this type).

If a new distro or distro version shares properties as part of a family of related distros, things become more complicated. In short, what needs to happen is that the parent distro of the family should be treated like the simple example above, and then each class representing a version of a child distro should inherit from the appropriate version of the parent distro from which it derives; but also each child should include a virtual class representing the unversioned child distro, which itself inherits from the virtual class of the parent distro, and it should explicitly set properties which must be derived from the unversioned child distro class. Also as with the previous example, supported distros should be added to L<Cpanel::OS::All>.

That is quite a lot to parse, so let's look at the example of RHEL and all of its supported children at the time of this writing:

    Cpanel::OS::Linux
     \_ Cpanel::OS::Rhel
         \_ Cpanel::OS::Almalinux
         \_ Cpanel::OS::Centos
         \_ Cpanel::OS::Cloudlinux
         \_ Cpanel::OS::Rhel
             \_ Cpanel::OS::Rhel7
                 \_ Cpanel::OS::Centos7         [C]
                 \_ Cpanel::OS::Cloudlinux7     [Cl]
                 \_ Cpanel::OS::Rhel8
                     \_ Cpanel::OS::Almalinux8  [A]
                     \_ Cpanel::OS::Centos8     [C]
                     \_ Cpanel::OS::Cloudlinux8 [Cl]

In this diagram, the levels indicate direct inheritance of the most recent class on the previous level, while the values in brackets indicate secondary import of the indicated class (C<[A]> being L<Cpanel::OS::Almalinux>, C<[C]> being L<Cpanel::OS::Centos>, and C<[Cl]> being L<Cpanel::OS::Cloudlinux>). Notice, for example, that the class for CloudLinux 7 is not a child of the class for CloudLinux 6, though both include the virtual class representing CloudLinux as a whole. Instead, the class for CloudLinux 7 inherits from the class for RHEL 7. Additionally, the properties the CloudLinux 7 module wants to re-use from the CloudLinux module must be explicitly set:

    use constant pretty_name => Cpanel::OS::Cloudlinux->pretty_name;

=item How do I see what is already available and add/edit/remove what I need?

The C<t/os.dump/cpanel-os-dump.md> file will contain a markdown-formatted representation of each property expressed by L<Cpanel::OS> for all supported OSes. Changes are performed by modifying L<Cpanel::OS::Linux> and any needed subclasses as described above.

=item A distro changed its behavior in the middle of a major version, and L<Cpanel::OS> needs to return a different value to accommodate these while still returning the old value for unaffected systems; how do I account for this?

If this is necessary, what can be done is to turn the property definition into a C<sub> whose return value depends on other properties. Because this logic exists within the L<Cpanel::OS> module subtree itself, it is acceptable to perform comparisons on distro(), major(), minor(), etc.

    sub kernel_package_pattern {
        return Cpanel::OS::minor() >= 6 ? "kernel-normal" : "kernel";
    }

That said, the C<t/os.dump/cpanel-os-dump.md> file will not record the existence of these kind of conditional values, so this must be kept in mind when verifying the correctness of properties.

=item How do I approach testing?

In short, test the code, not the data. The OSes and their data can/will change so testing the data just causes tech debt with no gain. Remember, a key idea is that OS data changing should not require us to change code logic to match. So ask yourself: "What am I really testing?"

Let’s work an example. Say we are writing tests for C<Foo>. OS A supports it, OS B does not.

We might be tempted to duplicate the data in the test and ensure each OS is what we expect it to be. This is not a valuable test as it doesn’t actually verify that C<Foo> works on OS A and not on OS B, so they could pass and yet C<Foo> support be totally broken.

This type of test just makes sure the data is what it is (i.e. not that its actually valid), adds more tech debt, and does not actually give us any useful results.

If you’re worried about the data being changed to an incorrect value then the test does not help that: If someone changes a value without verifying it is correct or not will just update the test without thinking. When data changes, like any other change, the dev should test it, the dev reviewer should be considering it, QA should test it, dev 3 review should be considering it, and the PO should be considering it. So it is unlikely to accidentally get changed to an incorrect value.

Along the same vein, we may be tempted to mock a Cpanel::OS object for OS A and OS B, in order to test that it errors out on B and does not error out on A.

What happens when one of those OSs go away? What happens when support for foo changes? Now your test needs updated to match reality. Instead ask, "What am I really testing?" In this case we are testing how C<Foo> behaves on supported and unsupported system based on a boolean for C<Foo>, so simply mock the property to be true and false, and verify C<Foo> behaves as it should under each case.

The same applies for tests that should be run on systems that support C<Foo> and skipped on C<Foo>. Skipping if the OS is B means the test needs to be changed when B adds support for it, or when a new OS is added that does not support it. Instead skip if the boolean in question if false. Of course that is vice versa on tests you want to run when on systems that do not support it.

The L<Mock::Cpanel::OS> module is available to make testing cases under all distros easier. See its documentation for more details. Specifically note that L<Mock::Cpanel::OS> only changes values returned by L<Cpanel::OS>, thus we recommend only using this with small tests where calls to the system are also mocked.

=item How can I make sure the cache does not cause me problems on my sandbox?

TODO alter if/when this goes away

It shouldn't, but for the sake of completeness:

For customers: it lives 24 hours && is cleared during upcp right after all the things are downloaded.

For developers: time based cache isn’t effective on sandboxes because we switch branches so often, but C<make clear-os-caches> will force it to run.

We could disable cache on dev box but did not because:

=over

=item 1. It would be a different path than binary builds which we try to avoid.

=item 2. We don’t do that w/ other caching things.

=back

=back

=head1 Worst Practices

There are certain anti-patterns which should for certain be avoided:

=over

=item * Comparing against C<Cpanel::OS::major>, C<Cpanel::OS::distro>, etc.

The purpose of L<Cpanel::OS> is to abstract OS-specific logic out of other code. Comparing against these outside of that module defeats the whole purpose. Please do not do this:

    if (Cpanel::OS::distro() eq 'cloudlinux') {                 # NOT OK
        do_the_thing();                                         # NOT OK
    }                                                           # NOT OK

Instead, create a new property and use that in your code:

    if (Cpanel::OS::supports_thing()) {                         # OK
        do_the_thing();                                         # OK
    }                                                           # OK

Note that it is still acceptable to I<use> these values outside of L<Cpanel::OS>, such as when populating a template:

    my ($distro, $major) = (Cpanel::OS::distro(), Cpanel::OS::major()); ## no critic(Cpanel::CpanelOS) explain why...
    my $url_base = "http://dl.project.test/pub/$distro/$major";         # OK
    print {$fh} "baseurl=$url_base\n";                                  # OK

In this case, because the questions being asked are directly regarding the identity of the distro and major release in creating data, and not in determining what logic to follow, the use is appropriate.

=item * Passing arguments to methods within L<Cpanel::OS>.

L<Cpanel::OS> is still designed primarily to be a repository of data, so having properties change on the basis of parameters passed into calls should be avoided.

    sub supports_thing ($version) { ... }                       # NOT OK

In this example, consider returning an arrayref of supported versions in addition to or instead of a support boolean:

    use constant supports_thing => 1;                           # OK
    use constant supported_thing_versions => [ qw(1.1 1.2) ];   # OK

Querying whether a value is in the list should be done with the list_contains_value() function if possible:

    if (Cpanel::OS::list_contains_value(supported_thing_versions => $current_thing_version)) { # OK
        ...;                                                                                   # OK
    }                                                                                          # OK

=item * Using existing properties as surrogates outside of their intended usage.

If your question about the system closely, but not exactly, matches one answered by an existing property, consider the consequences of a change in the answer to that existing question and whether it necessarily changes the answer to your own question. B<When in doubt, just go ahead and add a new property.> It is better for us to have redundant info than misused info; and if the new property turns out to be extraneous, we can easily find and replace it, if you chose its name wisely.

=item * Creating complementary properties, or misusing boolean states.

That said, one property should not act as the complement or negation of other properties:

    use constant supported_thing_versions => [ qw(1.1 1.2) ];   # NOT OK
    use constant unsupported_thing_versions => [ qw(1.0) ];     # NOT OK
    use constant expermental_thing_versions => [ qw(2.0) ];     # NOT OK

This may cause problems if code checks one list but not the other, and the user customized the system with ancient or brand-new versions, because it introduces the implicit states of being in neither list and being in both lists, which then has to be handled programmatically.

Ideally, there should be a single source of truth, but supplementary properties are of course acceptable and necessary:

    use constant supports_thing => 0;                           # OK
    use constant supported_thing_versions => [];                # OK

If you I<do> need more than two states, consider using a hashref:

    use Cpanel::Thing::Constants ( qw/SUPPORTED EXPERIMENTAL UNSUPPORTED/ ); # OK
                                                                             # OK
    use constant supported_thing_versions => {                               # OK
        '1.0' => UNSUPPORTED,                                                # OK
        '1.1' => SUPPORTED,                                                  # OK
        '1.2' => SUPPORTED,                                                  # OK
        '2.0' => EXPERIMENTAL,                                               # OK
    };                                                                       # OK

=back

=head1 Differences from the first version of L<Cpanel::OS>

The first version of L<Cpanel::OS> was introduced in version 96. That version stored all information as pure data within a C</usr/local/cpanel/os.d> directory. Unfortunately, it was found that this implementation caused problems during cPanel upgrades, specifically with respect to C<scripts/updatenow.static>. To better address the cases that script needs to be able to handle, the backend data storage was converted to pure Perl modules, and the calling interface was modified to facilitate implementing such a backend. Specifically, the first version had separate namespaces for booleans, simple values, and structures:

    my $supports_kernelcare = Cpanel::OS->instance->bool('supports_kernelcare');     # OLD
    my $ea4_openssl         = Cpanel::OS->instance->value('ea4/modern_openssl');   # OLD
    my $os_info             = Cpanel::OS->instance->struct('os_info');             # OLD

These are now implemented with a direct call into the common function namespace of the L<Cpanel::OS> module:

    my $supports_kernelcare = Cpanel::OS::supports_kernelcare();                   # NEW
    my $ea4_openssl         = Cpanel::OS::ea4_modern_openssl();                    # NEW
    my $os_info             = Cpanel::OS::os_info();                               # NEW

A namespace for 3rd-party extensions existed in the first version and has been dropped in this version. Overrides for specific OS minor releases have been removed, but equivalent results can be obtained by introducing simple logic into submodules (see L</HOWTO>).
