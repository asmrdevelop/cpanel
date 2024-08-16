package Whostmgr::API::1::ApplicationVersions;

# cpanel - Whostmgr/API/1/ApplicationVersions.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;
use Sort::Versions                    ();
use Cpanel::Exception                 ();
use Cpanel::LoadModule                ();
use Cpanel::DbUtils                   ();
use Cpanel::Config::LoadCpConf::Micro ();
use Cpanel::Pkgr                      ();
use Cpanel::EA4::Util                 ();
use Cpanel::OS                        ();
use Cpanel::ServerTasks               ();

use constant NEEDS_ROLE => {
    installed_versions  => undef,
    system_needs_reboot => undef,
};

our $CPCONF = Cpanel::Config::LoadCpConf::Micro::loadcpconf();
our @PACKAGES;
our $packages_hr = {};

my @package_items = qw{bind cpanel-clamav cpanel-php cpanel-exim cpanel-mailman munin openssh-server cpanel-pdns cpanel-roundcube p0f nscd rsyslog postgresql mysql mariadb cronie cron};

# MariaDB-server-10.3.13-1.el7.centos.x86_64

=encoding utf-8

=head1 NAME

Whostmgr::API::1::ApplicationVersions - A simple module for reporting versions of installed software

=head1 SYNOPSIS

Whostmgr::API::1::Application::versions::installed_versions(); # returns hashref

=head1 DESCRIPTION

Report version information for a number of components of a cPanel & WHM installation, including that of
cPanel & WHM. To provide consistency across usage, applications are always reported even if not installed.

=head2 installed_versions()

=head3 Purpose

Returns a hashref containing version information about installed applications. The contents of the
hashref will vary per server, and whether full system information was requested.

=head3 Arguments

    - $args - {
            'packages': when true (1) include a list of all RPMs organized into categories; when false (0) or not present the RPMs are not included
    }

=head3 Output

If an application is not installed a zero is reported for the version number. This allows the hash to be constant in output from system to system. Sample output below.

    "exim" => "4.88-1",
    "postgresql" =>  0,
    "proftpd" =>  0,
    "mysql" =>  "5.5",
    "dovecot" =>  "2.2.27 (c0f36b0)",
    ...
    "apache_php_versions" => [
      "5.5.38-1.1.3",
      "5.6.29-1.1.2",
      "7.0.14-1.1.2"
    ],

=cut

sub installed_versions {
    my ( $args, $metadata ) = @_;

    _load_packages();

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my $versions = _load_package_versions();
    $versions->{'mysql'}   = _mysql_information();
    $versions->{'mariadb'} = _mariadb_information();

    # We don't provide an easy way to determine whether MySQL or MariaDB is the chosen one
    if ( $versions->{'mariadb'} ) {
        $versions->{'mysql'}       = 0;
        $versions->{'mysql_build'} = 0;
    }

    $versions->{'easyapache'} = _easyapache_version();
    $versions->{'apache'}     = _apache_version();

    $versions->{'dovecot'}                  = _dovecot_version();
    $versions->{'operating_system_version'} = Cpanel::OS::major();         ## no critic(Cpanel::CpanelOS)
    $versions->{'operating_system_name'}    = Cpanel::OS::distro();        ## no critic(Cpanel::CpanelOS)
    $versions->{'linux_kernel'}             = _kernel_version();
    $versions->{'postgresql'}               = _get_postgresql_version();

    $versions->{'pureftpd'} = _pureftp_version();
    $versions->{'proftpd'}  = _proftp_version();

    $versions->{'spamd'} = _spamd_version();

    #Shims for cpanel provided system packages; don't break older callers
    $versions->{powerdns}   = delete $versions->{'cpanel-pdns'}      if exists $versions->{'cpanel-pdns'};
    $versions->{mailman}    = delete $versions->{'cpanel-mailman'}   if exists $versions->{'cpanel-mailman'};
    $versions->{clamav}     = delete $versions->{'cpanel-clamav'}    if exists $versions->{'cpanel-clamav'};
    $versions->{cpanel_php} = delete $versions->{'cpanel-php'}       if exists $versions->{'cpanel-php'};
    $versions->{roundcube}  = delete $versions->{'cpanel-roundcube'} if exists $versions->{'cpanel-roundcube'};

    _apache_php_version($versions);
    if ( !defined $args->{'packages'} || !$args->{'packages'} ) {
        delete $versions->{'cpanel_packages'};
        delete $versions->{'ea_4_packages'};
        delete $versions->{'os_packages'};
    }

    # DISPLAY: Rip off the arch and then rip off the elX if present
    foreach my $package ( keys(%$versions) ) {
        my $version_without_osarch = $versions->{$package};
        next if !defined $version_without_osarch || ref $version_without_osarch eq 'ARRAY';
        $version_without_osarch =~ s/\.([^\.]*)$//g;
        $version_without_osarch =~ s/\.el\d.*//g;
        $versions->{$package} = $version_without_osarch;
    }

    $versions->{'cpanel_and_whm'} = _product_information();

    return $versions;
}

sub _load_packages {    ## no critic qw(RequireFinalReturn)
    if ( !@PACKAGES ) {
        $packages_hr = Cpanel::Pkgr::get_version_with_arch_suffix(@package_items);
        @PACKAGES    = map { $_ . '-' . $packages_hr->{$_} } sort keys %{$packages_hr};
    }
}

sub _load_package_versions {

    my %data = map { $_ => 0 } @package_items;

    my ( @cpanel_packages, @ea4_packages, @system_packages );
    for my $p ( keys(%$packages_hr) ) {

        # For speed we always populate these arrays
        push( @cpanel_packages, $p ) if ( $p =~ m/^cpanel-/i );
        push( @ea4_packages,    $p ) if ( $p =~ m/^ea-/i );
        push( @system_packages, $p ) if ( $p !~ m/^ea-/i && $p !~ m/^cpanel-/i );

        $data{$p} = $packages_hr->{$p};
    }
    $data{'ea_4_packages'}   = [ sort @ea4_packages ];
    $data{'cpanel_packages'} = [ sort @cpanel_packages ];
    $data{'os_packages'}     = [ sort @system_packages ];
    return \%data;
}

sub _product_information {
    my $version = 0;
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::Version::Tiny');
        $version = $Cpanel::Version::Tiny::VERSION_BUILD;
    };
    return $version;
}

sub _mysql_information {
    my $installed = 0;
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Version');
        $installed = Cpanel::MysqlUtils::Version::current_mysql_version()->{'long'};
    };
    return $installed;
}

sub _mariadb_information {
    my $installed = 0;
    try {
        require Cpanel::MysqlUtils::Version;
        require Cpanel::MariaDB;
        my $version = Cpanel::MysqlUtils::Version::current_mysql_version()->{'long'};
        if ( Cpanel::MariaDB::version_is_mariadb($version) ) {
            $installed = $version;
        }
    };
    return $installed;
}

sub _easyapache_version {
    my $version = 4;
    $version = 3 if ( !-e '/etc/cpanel/ea4/is_ea4' );
    return $version;
}

sub _apache_version {
    my $version = 0;
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::HttpUtils::Version');
        $version = Cpanel::HttpUtils::Version::get_httpd_version();
    };
    return $version;
}

sub _apache_php_version {    ## no critic qw(RequireFinalReturn)
    my ($info) = @_;

    $info->{'apache_php_default_version'} = 0;
    $info->{'apache_php_versions'}        = [0];

    my $default_php_version = Cpanel::EA4::Util::get_default_php_version();
    $default_php_version =~ s/\.//g;
    my $default_php = "ea-php$default_php_version";
    my @apache_php;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Httpd::EA4');
    if ( Cpanel::Config::Httpd::EA4::is_ea4() ) {
        try {
            Cpanel::LoadModule::load_perl_module('Cpanel::ProgLang');
            my $php = Cpanel::ProgLang->new( type => 'php' );

            $default_php = $php->get_system_default_package();
        };

        #ea-php54-5.4.45-15.15.1.x86_64
        #ea-php99-9.9.24-1.1.1.cpanel.x86_64
        foreach my $p (@PACKAGES) {
            next if $p !~ m/^ea-php/i;
            if ( $p =~ m/^ea-php[\d]+-([\d.-]+)\.[cpanel|x86]/ ) {
                push( @apache_php, $1 );
            }
            if ( $p =~ m/^${default_php}-([\d.-]+)\.[cpanel|x86]/ ) {
                $info->{'apache_php_default_version'} = $1;
            }
        }

        if (@apache_php) {
            $info->{'apache_php_versions'} = \@apache_php;
        }
    }
}

sub _dovecot_version {
    my $version = 0;
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::AdvConfig::dovecot::utils');
        $version = Cpanel::AdvConfig::dovecot::utils::get_dovecot_version();
    };
    return $version;
}

sub _get_postgresql_version {
    my $version = 0;
    try {
        if ( Cpanel::DbUtils::find_psql() ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::PostgresUtils');
            $version = Cpanel::PostgresUtils::get_version();
        }
    };
    return $version;
}

sub _proftp_version {
    my $version = 0;
    try {
        if ( $CPCONF->{'ftpserver'} eq 'proftpd' ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::FtpUtils::Config::Proftpd');
            my $f = Cpanel::FtpUtils::Config::Proftpd->new();
            $version = $f->get_version();
        }
    };
    return $version;
}

sub _pureftp_version {
    my $version = 0;
    try {
        if ( $CPCONF->{'ftpserver'} eq 'pure-ftpd' ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::FtpUtils::Config::Pureftpd');
            my $f = Cpanel::FtpUtils::Config::Pureftpd->new();
            $version = $f->get_version();
        }
    };
    return $version;
}

sub _kernel_version {
    my $version = 0;
    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::Kernel');
        $version = Cpanel::Kernel::get_running_version();
    };
    return $version;
}

sub _spamd_version {
    my $version = 0;
    try {
        require Mail::SpamAssassin;
        require version;
        $version = version->parse($Mail::SpamAssassin::VERSION)->normal();
        substr( $version, 0, 1, '' ) if substr( $version, 0, 1 ) eq 'v';
        $version = 0                 if $version eq '0.0.0';
    };
    return $version;
}

=head2 system_needs_reboot ()

=head3 Purpose

Returns 1 if the kernel that will be booted is different than the kernel currently
running otherwise returns 0.

=head3 Arguments

    None

=head3 Output

    {
        'needs_reboot' => 1,
        'details'      => { 'kernel' => 1 },
    }

=cut

sub system_needs_reboot {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my %details;

    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Utils');
        $details{'quota'} = 1 if Cpanel::Quota::Utils::reboot_required();
    }
    catch {
        $metadata->{result} = 0;
        $metadata->{reason} = Cpanel::Exception::get_string_no_id($_);
    };

    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::ProcessCheck::Outdated');
        my $packages = Cpanel::ProcessCheck::Outdated::reboot_suggested();
        if ($packages) {
            if ( delete $packages->{kernel} ) {
                $details{updates} = $packages if %$packages;    # If the kernel was the only item listed, omit this rationale - the kernel check will handle that.
            }
            else {
                $details{updates} = $packages;                  # Even if there are no packages listed, this allows a reboot suggestion to go through.
            }
        }
    }
    catch {
        if ( !ref $_ || !$_->isa('Cpanel::Exception::Unsupported') ) {
            $metadata->{result} = 0;
            $metadata->{reason} = Cpanel::Exception::get_string_no_id($_);
        }
    };

    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::Kernel::Status');
        my $status = Cpanel::Kernel::Status::reboot_status();
        if ( exists $status->{reboot_required} and $status->{reboot_required} eq 1 ) {
            $details{kernel} = {
                boot_version    => $status->{boot_version},
                running_version => $status->{running_version},
            };
        }
    }
    catch {
        if ( !ref $_ || !$_->isa('Cpanel::Exception::Unsupported') ) {
            $metadata->{result} = 0;
            $metadata->{reason} = Cpanel::Exception::get_string_no_id($_);
        }
    };

    # Trigger a cache update, so the cached value which is displayed in the UI
    # will be in agreement with the live results.
    # Since the code to update the cache calls this function, do not trigger
    # the cache update if called from there.
    if ( !defined $args->{'no_cache_update'} || !$args->{'no_cache_update'} ) {
        Cpanel::ServerTasks::schedule_task( ['SystemTasks'], 5, "recache_system_reboot_data" );
    }

    return {
        'needs_reboot' => %details ? 1 : 0,
        'details'      => \%details,
    };
}

1;
