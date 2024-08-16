package Cpanel::RPM::Versions::File;

# cpanel - Cpanel/RPM/Versions/File.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Parallelizer              ();
use Cpanel::Binaries                  ();
use Cpanel::Config::Sources           ();
use Cpanel::Crypt::GPG::Settings      ();
use Cpanel::Exception                 ();
use Cpanel::FileUtils::Link           ();
use Cpanel::FileUtils::TouchFile      ();
use Cpanel::OS                        ();
use Cpanel::RPM::Versions::Directory  ();
use Cpanel::RPM::Versions::File::YAML ();
use Cpanel::RPM::Versions::Pkgr       ();
use Cpanel::SafeDir::MK               ();
use Cpanel::SafeRun::Errors           ();
use Cpanel::Sync::Digest              ();
use Cpanel::URL                       ();
use Cpanel::Update::Logger            ();
use Cpanel::Version                   ();
use Cpanel::LoadFile                  ();

use parent 'Cpanel::Update::Base';

our $install_rpms_in_progress_file = '/var/cpanel/install_rpms_in_progress';

use Cpanel::ConfigFiles::RpmVersions ();

my $PERL_MAJOR = Cpanel::Binaries::PERL_MAJOR();
my $PHP_MAJOR  = Cpanel::Binaries::PHP_MAJOR();

# Defer compontents not needed for EA4 and MySQL installs
# so we can get these started right away on first install.
# Once they are going we will install these before the
# cPanel post install scripts run
my %components_to_defer_on_firstinstall = (
    "perl${PERL_MAJOR}-graph"            => 1,
    "perl${PERL_MAJOR}-git"              => 1,
    "perl${PERL_MAJOR}-cpanel-dev"       => 1,
    "perl${PERL_MAJOR}-export"           => 1,
    "perl${PERL_MAJOR}-tooling"          => 1,
    "perl${PERL_MAJOR}-dav"              => 1,
    "perl${PERL_MAJOR}-oidc"             => 1,
    "perl${PERL_MAJOR}-spamassassin"     => 1,
    "perl${PERL_MAJOR}-backups"          => 1,
    "perl${PERL_MAJOR}-wordpress-plugin" => 1,
    "perl${PERL_MAJOR}-idn"              => 1,
    'cpanel-rrdtool'                     => 1,
);

my %targets_to_defer_on_firstinstall = (
    'p0f'                    => 1,
    'phpmy'                  => 1,
    'git'                    => 1,
    'userinterface'          => 1,
    'userinterface-debug'    => 1,
    'sitepublisher'          => 1,
    'pure-ftpd'              => 1,
    'exim'                   => 1,
    'spamassassin'           => 1,
    'roundcube'              => 1,
    'composer'               => 1,
    'cpanel-deferrable'      => 1,
    'webalizer'              => 1,
    'analog'                 => 1,
    'awstats'                => 1,
    '3rdparty'               => 1,
    "cpanel-php${PHP_MAJOR}" => 1,
);

# Only check this once.
# (undef = not checked yet)
# (0 = was not running)
# (1 = was running)
our $_tailwatchd_was_running_when_rpm_transaction_began;

=head1 NAME

Cpanel::RPM::Versions::File - RPM manager for cPanel provided RPMs.

=head1 USAGE

    # This code is called from setup scripts (i.e. setupnameserver)
    my $versions = Cpanel::RPM::Versions::File->new( { 'only_targets' => [qw/powerdns/]} )

    # Called like this from updatenow
    my $versions = Cpanel::RPM::Versions::File->new();

    # When the object is in place, it's used like this for the most part:

    # Download the Packages to a temp location under /ULC
    $versions->stage();
    ...

    # Install/Uninstall Packages as needed
    $versions->commit_changes();


=head1 DESCRIPTION

This module is used to manage what files should be installed on a cPanel system based
primarily on the contents of etc/rpm.versions. Customizations are allowed to override
this via its sister module Cpanel::RPM::Versions::Directory.

=head1 METHODS

=over 4

=item B<new>

Called to initialize the object. Ultimatley loads in all data needed to know what Packages need
to be installed/uninstalled.

=back

=cut

sub new ( $class, $args = undef ) {

    my $self = $class->init($args);
    bless $self, $class;

    return $self;
}

sub _need_object ($self) {
    $self->isa(__PACKAGE__) or do {
        my @caller = caller(1);
        die("You must call $caller[3] as a method at $caller[1] line $caller[2].\n");
    };
    return;
}

sub obsolete          ( $self, $key = undef ) { return $self->generic_get_method( 'obsolete',          $key ) }
sub unsupported_rpms  ( $self, $key = undef ) { return $self->generic_get_method( 'unsupported_rpms',  $key ) }
sub url_templates     ( $self, $key = undef ) { return $self->generic_get_method( 'url_templates',     $key ) }
sub rpm_groups        ( $self, $key = undef ) { return $self->generic_get_method( 'rpm_groups',        $key ) }
sub srpm_sub_packages ( $self, $key = undef ) { return $self->generic_get_method( 'srpm_sub_packages', $key ) }
sub target_settings   ( $self, $key = undef ) { return $self->generic_get_method( 'target_settings',   $key ) }
sub file_format       ( $self, $key = undef ) { return $self->generic_get_method( 'file_format',       $key ) }
sub location_keys     ( $self, $key = undef ) { return $self->generic_get_method( 'location_keys',     $key ) }

sub rpm_locations ( $self, $key = undef ) {
    my $rpm_locations = $self->generic_get_method( 'rpm_locations', $key ) // {};

    # expand setup location for sub_packages
    if ( my $srpm_sub_packages = $self->srpm_sub_packages ) {

        foreach my $main_pkg ( sort keys $srpm_sub_packages->%* ) {
            my $location = $rpm_locations->{$main_pkg};
            next unless defined $location;

            foreach my $subpkg ( $srpm_sub_packages->{$main_pkg}->@* ) {
                next if $subpkg eq $main_pkg;
                $rpm_locations->{$subpkg} = $location;
            }
        }
    }

    return $rpm_locations;
}

sub srpm_versions ( $self, $key = undef ) {

    my $srpms_v = $self->generic_get_method( 'srpm_versions', $key );

    return $srpms_v unless ref $srpms_v eq 'HASH';

    # advertise the expected '~distro' version in the release tag of the src.rpm
    foreach my $srpm ( keys $srpms_v->%* ) {
        my $v = $srpms_v->{$srpm};
        next unless $v =~ qr{\.cp\d{3}$}a;    # >= cp108
        $srpms_v->{$srpm} .= Cpanel::OS::package_release_distro_tag();
    }

    # expand setup srpm_versions for sub_packages
    if ( my $srpm_sub_packages = $self->srpm_sub_packages ) {

        foreach my $main_pkg ( sort keys $srpm_sub_packages->%* ) {
            my $v = $srpms_v->{$main_pkg};

            if ( !defined $v ) {
                $self->logger->warning("Cannot find version for srpm_sub_packages '$main_pkg'");
                next;
            }

            foreach my $subpkg ( $srpm_sub_packages->{$main_pkg}->@* ) {
                next if $subpkg eq $main_pkg;
                $srpms_v->{$subpkg} = $v;
            }
        }
    }

    return $srpms_v;
}

sub generic_get_method ( $self, $method, $key = undef ) {
    _need_object($self);

    if ($key) {    # Supply from one of the files in rpm.versions.d
        my $value = $self->dir_files()->fetch( { 'section' => $method, 'key' => $key } );

        if ($value) {
            return $value;
        }
        else {     # supply from etc/rpm.versions
            return $self->config_file()->fetch( { 'section' => $method, 'key' => $key } );
        }
    }
    else {

        # rpm.versions.d data
        my $dir_section = $self->dir_files()->fetch( { 'section' => $method } );

        # etc/rpm.versions data
        my $config_section = $self->config_file()->fetch( { 'section' => $method } );

        @{$config_section}{ keys %{$dir_section} } = values %{$dir_section};

        return $config_section;
    }
}

sub set_target_settings ( $self, $args ) {

    _need_object($self);

    my $key = $args->{'key'} or return 'No target name passed to set target_settings';
    ref $key eq 'ARRAY'      or return 'No target name array passed to set target_settings';
    scalar @$key == 1        or return 'Unexpected target_settings name (' . join( '.', @$key ) . ') passed to set target_settings';
    my $target = $key->[0]   or return "A target must be passed in order to set target_settings";

    if ( !$self->target_settings->{$target} ) {
        return "Attempted to set unknown target '$target'";
    }

    my $value = $args->{'value'} or return "No value passed to set target_settings.$target";

    unless ( $value =~ m/^((un)?installed|unmanaged)$/ ) {
        return "Unrecoginzed value '$value' set for target '$target'. Supported values are: installed, uninstalled, unmanaged.";
    }

    return $self->generic_set_method( 'target_settings', $args );
}

sub set_srpm_versions ( $self, $args ) {

    _need_object($self);

    my $key = $args->{'key'} or return 'No srpm name passed to set srpm_versions';
    ref $key eq 'ARRAY'      or return 'No srpm name array passed to set srpm_versions';

    scalar @$key == 1 or return 'Unexpected srpm name (' . join( '.', @$key ) . ') passed to set srpm_versions';

    my $srpm = $key->[0] or return "A valid srpm name must be passed in order to set the value of any srpm";

    if ( !$self->srpm_versions->{$srpm} ) {
        return "Attempted to set the version of an unknown srpm '$srpm'";
    }

    return $self->generic_set_method( 'srpm_versions', $args );
}

sub set_obsolete          ( $self, $args ) { return $self->generic_set_method( 'obsolete',          $args ) }
sub set_unsupported_rpms  ( $self, $args ) { return $self->generic_set_method( 'unsupported_rpms',  $args ) }
sub set_url_templates     ( $self, $args ) { return $self->generic_set_method( 'url_templates',     $args ) }
sub set_rpm_groups        ( $self, $args ) { return $self->generic_set_method( 'rpm_groups',        $args ) }
sub set_srpm_sub_packages ( $self, $args ) { return $self->generic_set_method( 'srpm_sub_packages', $args ) }
sub set_rpm_locations     ( $self, $args ) { return $self->generic_set_method( 'rpm_locations',     $args ) }
sub set_location_keys     ( $self, $args ) { return $self->generic_set_method( 'location_keys',     $args ) }
sub set_install_targets   ( $self, $args ) { return $self->generic_set_method( 'install_targets',   $args ) }

sub generic_set_method ( $self, $method, $args ) {
    my $key   = $args->{'key'};
    my $value = $args->{'value'};

    _need_object($self);

    $self->dir_files()->set( { 'section' => $method, 'key' => $key, 'value' => $value } );

    return;
}

sub delete_obsolete          ( $self, $args ) { return $self->generic_delete_method( 'obsolete',          $args ) }
sub delete_unsupported_rpms  ( $self, $args ) { return $self->generic_delete_method( 'unsupported_rpms',  $args ) }
sub delete_url_templates     ( $self, $args ) { return $self->generic_delete_method( 'url_templates',     $args ) }
sub delete_rpm_groups        ( $self, $args ) { return $self->generic_delete_method( 'rpm_groups',        $args ) }
sub delete_srpm_sub_packages ( $self, $args ) { return $self->generic_delete_method( 'srpm_sub_packages', $args ) }
sub delete_srpm_versions     ( $self, $args ) { return $self->generic_delete_method( 'srpm_versions',     $args ) }
sub delete_rpm_locations     ( $self, $args ) { return $self->generic_delete_method( 'rpm_locations',     $args ) }
sub delete_target_settings   ( $self, $args ) { return $self->generic_delete_method( 'target_settings',   $args ) }
sub delete_location_keys     ( $self, $args ) { return $self->generic_delete_method( 'location_keys',     $args ) }
sub delete_install_targets   ( $self, $args ) { return $self->generic_delete_method( 'install_targets',   $args ) }

sub generic_delete_method ( $self, $method, $args ) {
    my $key   = $args->{'key'};
    my $value = $args->{'value'};

    _need_object($self);

    return $self->dir_files()->delete( { 'section' => $method, 'key' => $key, 'value' => $value } );
}

sub init ( $class, $args = undef ) {
    $args ||= {};    # New can be empty.
    die 'New takes a hash reference only.' if ( ref $args ne 'HASH' );

    # validate args are in the known list *cough* setupnameserver
    foreach my $arg ( keys %$args ) {
        die("Unknown parameter: '$arg'") unless ( grep { $_ eq $arg } qw/firstinstall mysql_targets only_targets temp_dir file directory logger rpm_install http_client dir_object pkgr/ );
    }

    if ( $args->{'http_client'} ) {
        $args->{'http_client'}->isa('Cpanel::HttpRequest') or die "http_client must be a Cpanel::HttpRequest";

    }

    die 'The value of only_targets must be an array_ref.' if ( exists $args->{'only_targets'} && ref $args->{'only_targets'} ne 'ARRAY' );

    die 'The value of rpm_install must be an array_ref.' if ( exists $args->{'rpm_install'} && ref $args->{'rpm_install'} ne 'ARRAY' );

    die 'only_targets and rpm_install are mutually exclusive.' if ( exists $args->{'rpm_install'} && exists $args->{'only_targets'} );

    my $file = $args->{'file'}      || $Cpanel::ConfigFiles::RpmVersions::RPM_VERSIONS_FILE;
    my $dir  = $args->{'directory'} || '/var/cpanel/rpm.versions.d';

    # Init a logger if one is not provided. It will go to stdout only.
    $args->{'logger'} ||= Cpanel::Update::Logger->new( { 'stdout' => 1, 'log_level' => 'debug' } );

    if ( !-e $file ) {
        die "$file does not exist.\n";
    }

    my @digest_algorithms = Cpanel::Crypt::GPG::Settings::allowed_digest_algorithms();

    my $pkgr = $args->{'pkgr'} || Cpanel::RPM::Versions::Pkgr->new( 'logger' => $args->{'logger'} );
    return {
        'config_file'           => Cpanel::RPM::Versions::File::YAML->new( { file => $file } ),
        'dir_files'             => $args->{'dir_object'} || Cpanel::RPM::Versions::Directory->new( { directory => $dir, 'logger' => $args->{'logger'}, mysql_targets => $args->{'mysql_targets'} } ),
        'only_targets'          => $args->{'only_targets'},
        'rpm_install'           => $args->{'rpm_install'},
        'logger'                => $args->{'logger'},
        'firstinstall'          => $args->{'firstinstall'},
        'temp_dir'              => $args->{'temp_dir'} || '/usr/local/cpanel/tmp/rpm_downloads',
        'digest_algorithms'     => \@digest_algorithms,
        'max_download_attempts' => 5,
        'request'               => $args->{'http_client'},
        'pkgr'                  => $pkgr,
        'packaging'             => $pkgr->{'packaging'},
    };
}

sub pkgr      ($self) { return $self->{'pkgr'} }
sub packaging ($self) { return $self->{'packaging'} }

sub is_rpm ($self) { return $self->{'packaging'} eq 'rpm' ? 1 : 0 }
sub is_deb ($self) { return $self->{'packaging'} eq 'deb' ? 1 : 0 }

sub logger ($self) {
    _need_object($self);

    $self->{logger} //= Cpanel::Update::Logger->new( { 'stdout' => 1, 'log_level' => 'debug' } );

    return $self->{logger};
}

# ,----
# | Utility methods
# `----

sub http_request ($self) {
    _need_object($self);

    return $self->{'request'} if $self->{'request'};

    require Cpanel::HttpRequest;
    $self->{'request'} = Cpanel::HttpRequest->new(
        'retry_dns'  => 0,
        'hideOutput' => 1,
        'logger'     => $self->logger,
    );

    die "Failed to instantiate Cpanel::HttpRequest object." if !$self->{'request'};
    return $self->{'request'};
}

sub cpsources ($self) {
    _need_object($self);

    $self->{'cpsources'} ||= Cpanel::Config::Sources::loadcpsources();
    return $self->{'cpsources'};
}

sub config_file ($self) {
    _need_object($self);

    return $self->{'config_file'};
}

sub dir_files ($self) {
    _need_object($self);

    return $self->{'dir_files'};
}

sub install_targets ( $self, $key, $filter ) {
    _need_object($self);

    die unless $key;

    my $method = 'install_targets';

    if ($key) {
        my $value = $self->dir_files()->fetch( { 'section' => $method, 'key' => $key } );
        if ( !$value ) {
            $value = $self->config_file()->fetch( { 'section' => $method, 'key' => $key } );
        }

        if ( ref $value eq 'HASH' ) {
            my @flat_list;

            my @dependencies;
            if ( ref $value->{'dependencies'} eq 'ARRAY' ) {
                push @dependencies, @{ $value->{'dependencies'} || [] } unless $filter eq 'uninstalled';
            }
            else {
                push @dependencies, $value->{'dependencies'} unless $filter eq 'uninstalled';
            }

            if ( $self->{firstinstall} && @dependencies ) {
                @dependencies = grep { length && !$components_to_defer_on_firstinstall{$_} } @dependencies;
            }

            push @flat_list, @dependencies;

            my @components;
            if ( ref $value->{'components'} eq 'ARRAY' ) {
                push @components, @{ $value->{'components'} || [] };
            }
            else {
                push @components, $value->{'components'};
            }

            if ( $self->{firstinstall} && @components ) {
                @components = grep { length && !$components_to_defer_on_firstinstall{$_} } @components;
            }

            push @flat_list, @components;

            return \@flat_list;
        }
        elsif ( ref $value eq 'ARRAY' ) {
            return $value;
        }
        else {
            return;
        }
    }
    else {
        my $dir_section    = $self->dir_files()->fetch( { 'section' => $method } );
        my $config_section = $self->config_file()->fetch( { 'section' => $method } );

        foreach my $current_key ( keys %{$dir_section} ) {
            $config_section->{$current_key} = $dir_section->{$current_key};
        }

        return $config_section;
    }
}

=over

=item B<unsupported_rpms_for_this_distro>

The list of Packages this distro's major version cannot support.

For example, Systemd didn't show up until Red Hat 7 so wouldn't be available in 6.

=back

=cut

sub unsupported_rpms_for_this_distro ($self) {
    _need_object($self);

    my $stash  = $self->global_template_stash;
    my $distro = $stash->{'dist'} eq 'ubuntu' ? 'ubuntu' : 'redhat';

    return $self->unsupported_rpms->{ sprintf( "%s%s", $distro, $stash->{'dist_ver'} // '' ) } // [];
}

=over

=item B<expand_to_srpm_versions_from_target>

Expand a single target or package_group to the srpm_versions list.

=back

=cut

sub expand_to_srpm_versions_from_target ( $self, $target ) {
    _need_object($self);

    die unless $target;

    # Return value
    my $package_groups      = $self->rpm_groups_cached();
    my $package_group       = $package_groups->{$target} || [$target];
    my $srpm_versions       = $self->srpm_versions_cached();
    my $packages_to_exclude = $self->unsupported_rpms_for_this_distro;

    my $packages_to_return = { map { $srpm_versions->{$_} ? ( $_ => $srpm_versions->{$_} ) : () } @{$package_group} };
    delete $packages_to_return->{$_} foreach @$packages_to_exclude;

    return $packages_to_return;
}

=over

=item B<expand_target_to_rpms>

Expands a target to all of the Packages it provides.

=back

=cut

sub expand_target_to_rpms ( $self, $target = undef ) {

    _need_object($self);

    return if !$target;

    # Expand all targets to a hash of srpm_versions and store it in the hash ref $package
    my $package_map = $self->expand_to_srpm_versions_from_target($target);

    if ( my $temp_map = $self->find_from_srpm_sub_packages($target) ) {
        @{$package_map}{ keys %$temp_map } = values %$temp_map;
    }

    return $package_map;
}

=over

=item B<install_hash>

Returns a list (hash) of what Packages should be installed that are not already.
The hash keys are the Package names. The hash values are the version and release
numbers of the Packages.

=back

=cut

sub install_hash ( $self, $installed_rpms = undef, $upgraded_rpms = undef ) {

    my $ihash      = $installed_rpms || $self->list_rpms_in_state('installed');
    my $to_install = {};
    foreach my $package ( keys %{$ihash} ) {
        if ( !$self->_is_installed_in_os( $package, $ihash->{$package} ) ) {    # If the Package is already installed in the OS there is no need to reinstall.
            $to_install->{$package} = $ihash->{$package};
        }
    }

    my $uhash = $upgraded_rpms || $self->list_rpms_in_state('upgraded');
    foreach my $package ( keys %{$uhash} ) {
        if ( $self->_is_installed_in_os($package) && !$self->_is_installed_in_os( $package, $uhash->{$package} ) ) {    # Only if the Package is already installed but not up to date.
            $to_install->{$package} = $uhash->{$package};
        }
    }

    $self->{'install_hash'} = $to_install;
    return $to_install;
}

=over

=item B<uninstall_hash>

Returns a list (hash) of Packages that do not need to be installed based on current
settings that can now be removed. The hash values are the version and release
numbers of the Packages.

=back

=cut

sub uninstall_hash ( $self, $installed_rpms = undef, $uninstalled_rpms = undef ) {
    _need_object($self);

    my $ulist = $uninstalled_rpms || $self->list_rpms_in_state('uninstalled');

    # uninstall must use the list of what "would be" installed to determing what to uninstall.
    # In other words, don't use ->install_hash here.
    my $ilist = $installed_rpms || $self->list_rpms_in_state("installed");

    my $to_uninstall = {};

    foreach my $package ( keys %{$ulist} ) {
        if ( !exists $ilist->{$package} && $self->_is_installed_in_os($package) ) {    # Don't uninstall if the Package is found in
            $to_uninstall->{$package} = $ulist->{$package};                            # the list of things to be installed
        }
    }

    my $obsolete_rpms = $self->obsolete;
    foreach my $package ( keys %{$obsolete_rpms} ) {
        if ( !exists $ilist->{$package} && $self->_is_installed_in_os($package) ) {    # Don't uninstall if the Package is found in
            $to_uninstall->{$package} = q[obsolete];                                   # the list of things to be installed
        }
    }

    return $to_uninstall;
}

sub list_rpms_in_state ( $self, $filter = 'installed' ) {

    _need_object($self);

    my @targets = $self->get_all_targets_in_state($filter) or return {};

    # Remove 1st install targets from the list of targets being asked about.
    if ( $self->{firstinstall} && @targets ) {
        @targets = grep { length && !$targets_to_defer_on_firstinstall{$_} } @targets;
    }

    if ( $self->{'only_targets'} ) {

        # Filter out the global list based on only_targets list.
        my @only_targets_in_state;
        foreach my $target ( @{ $self->{'only_targets'} } ) {
            push @only_targets_in_state, $target if ( grep { $_ eq $target } @targets );
        }
        @targets = @only_targets_in_state;
    }

    my %packages;
    if ( $self->{'rpm_install'} ) {
        my $srpm_versions = $self->srpm_versions_cached();    # already expanded
        foreach my $target ( @{ $self->{'rpm_install'} } ) {
            if ( defined $srpm_versions->{$target} ) {
                $packages{$target} = $srpm_versions->{$target};
            }
        }

        return \%packages;
    }

    foreach my $target (@targets) {

        my $modules = $self->install_targets( $target, $filter ) // [];
        push @$modules, $target unless scalar @$modules;

        foreach my $module ( @{$modules} ) {
            foreach my $sub_target ( $self->expand_target_to_rpms($module) ) {
                @packages{ keys %{$sub_target} } = values %{$sub_target};
            }
        }
    }

    return \%packages;
}

=over

=item B<get_template_name>

This function determines which template a given package is supposed to use, taking
into account srpm_sub_packages, which the stock rpm_locations is incapable of.

=back

=cut

sub get_template_name ( $self, $package ) {
    die unless $package;

    my $location = $self->rpm_locations_cached()->{$package};
    $location //= 'default';

    my $packaging_system = $self->packaging;

    # If it's not an rpm system, we inject deb_ in front of the template name since it's going to be in a different location.
    $location = "${packaging_system}_${location}" if $packaging_system ne 'rpm';

    return $location;
}

=over

=item B<load_template_stash>

This function initializes the template stash with a fixed set of variables that
are common to all packages.

=back

=cut

sub global_template_stash ($self) {

    # return a copy
    return { $self->{'template_stash'}->%* } if ref $self->{'template_stash'};

    $self->{'template_stash'} = {
        'httpupdate' => $self->cpsources->{'HTTPUPDATE'},
        'lts'        => Cpanel::Version::get_lts(),
        'dist'       => Cpanel::OS::rpm_versions_system(),
        'dist_ver'   => Cpanel::OS::major(),                 ## no critic(Cpanel::CpanelOS) rpm.versions template
        'arch'       => Cpanel::OS::packages_arch(),
    };

    # Legacy template variables for RPM. we're going to stop using these.
    if ( $self->is_rpm ) {
        $self->{'template_stash'}->{'rpm_dist'}     = $self->{'template_stash'}->{'dist'};
        $self->{'template_stash'}->{'rpm_dist_ver'} = $self->{'template_stash'}->{'dist_ver'};
        $self->{'template_stash'}->{'rpm_arch'}     = $self->{'template_stash'}->{'arch'};
    }

    return { $self->{'template_stash'}->%* };
}

sub package_to_source ( $self, $package ) {
    return $self->{'pkg_to_source_map'}->{$package} || $package if $self->{'pkg_to_source_map'};

    my $subs = $self->srpm_sub_packages;
    foreach my $source_package ( keys %$subs ) {
        foreach my $sub_package ( $subs->{$source_package}->@* ) {
            $self->{'pkg_to_source_map'}->{$sub_package} = $source_package;
        }
    }

    return $self->{'pkg_to_source_map'}->{$package} || $package;
}

=over

=item B<url>

This function takes an rpm and version and determines it's URL based on all
rpm.versions files.

=back

=cut

sub url ( $self, $package, $version ) {
    _need_object($self);

    $package or die;
    $version or die("No version provided for $package");

    my $template_name = $self->get_template_name($package);

    my $url_template = $self->url_templates_cached($template_name) or die("The Package '$package-$version' does not have a valid URL template '$template_name'");    ###doc###

    my ( $package_version, $package_revision ) = split /-/, $version, 2;

    # Pre-build the static stash members once for the life of this object.

    my $lowest_cpanel_version_supported = 'unknown';
    if ( defined $package_revision ) {
        if ( $package_revision =~ m/cp(\d{3})(?:~.+)?$/a ) {    # we drop the 11 in cp11 starting with cp108
            $lowest_cpanel_version_supported = "11.$1";
        }
        elsif ( $package_revision =~ m/cp11(\d+)$/a ) {
            $lowest_cpanel_version_supported = "11.$1";
        }
    }
    my $source_package = $self->package_to_source($package);

    my $vars = {
        $self->global_template_stash->%*,
        'source_package'                  => $source_package,
        'package'                         => $package,
        'package_version'                 => $package_version,
        'package_revision'                => $package_revision,
        'lowest_cpanel_version_supported' => $lowest_cpanel_version_supported,
    };

    my $output = process_template( $url_template, $vars );

    return $output;
}

sub process_template ( $template = undef, $vars = undef ) {
    return $template if !$template;
    return $template unless $vars && ref $vars eq 'HASH';
    return $template =~ s{\[\%\s+(\S+)\s+\%\]}{length $vars->{$1} ? $vars->{$1} : ''}msger;
}

sub download ( $self, $url, $dest_file, $opts = do { {} } ) {

    return { 'status' => 0, 'file' => $dest_file } unless ( $url && $dest_file );

    my $res;
    $self->logger->info("Downloading $url") unless $self->{'did_preinstall'};    # Don't say this if we already did a first download pass.

    my $parsed_url = Cpanel::URL::parse($url);

    my %request_opts = (
        'host'       => $parsed_url->{'host'},
        'url'        => $parsed_url->{'uri'},
        'destfile'   => $dest_file,
        'protocol'   => 0,
        'method'     => 'GET',
        'signed'     => $opts->{'signed'},
        'vendor'     => $opts->{'vendor'},
        'categories' => $opts->{'categories'},
    );

    local $@;
    eval {
        $res = $self->http_request()->request(%request_opts);
        -e $dest_file or die("Could not download '$url' to '$dest_file'");
        -z _ and die("Tried to download '$url' to '$dest_file' but the file is zero bytes");
    };

    if ($@) {
        my $err = $@;

        if ( $opts->{'no_die_on_error'} ) {
            $self->logger->warning($err);
        }
        else {
            $self->logger->fatal($err);
            die $err;
        }
    }

    $self->{'files_downloaded'} ||= [];
    push @{ $self->{'files_downloaded'} }, $dest_file;

    return { 'status' => $res, 'file' => $dest_file };
}

sub stage_digests ( $self, $download_hash, $algorithm, $opts_ref = do { {} } ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    die unless $download_hash;
    die unless $algorithm;

    my $temp_dir = $self->{'temp_dir'};
    unlink( glob( $temp_dir . '/*.' . $algorithm ) );

    my @downloads;

    my %digests;
    my %download_queued;
    for my $package ( sort keys %{$download_hash} ) {
        my $url      = $download_hash->{$package}->{url};
        my $location = $download_hash->{$package}->{location};

        my $dest_file = $url;
        $dest_file =~ s{^[^\/]+:\/\/}{};    # Strip https?://

        # For debian, strip off the URL after pool. All digests are in the same location for debian.
        if ( $self->is_deb ) {
            $dest_file =~ s{(/pool/).+}{/pool};
            $url       =~ s{(/pool/).+}{/pool};
        }

        $dest_file =~ s{/}{_}g;             # Replace / with _
        $dest_file = $temp_dir . '/' . $dest_file . '.' . $algorithm;
        next if $download_queued{$dest_file};

        my $download_url = $url . '/' . $algorithm;
        my $location_key = $self->location_keys()->{$location};

        my $vendor     = $location_key->{vendor};
        my $categories = $location_key->{categories};
        my $signed     = $location_key->{disable_signatures} ? 0 : 1;

        if ($signed) {

            # prime the gpg object
            $self->http_request()->get_crypt_gpg_vendorkey_verify( vendor => $vendor, categories => $categories );
        }

        $download_queued{$dest_file} = 1;
        push @downloads,
          {
            'dest_file'    => $dest_file,
            'download_url' => $download_url,
            'url'          => $url,
            'opts'         => { signed => $signed, vendor => $vendor, categories => $categories, no_die_on_error => 1 }
          };
    }

    if (@downloads) {
        my $process_limit = $opts_ref->{'max_sync_children'} ||= $self->calculate_max_sync_children();
        my $parallelizer  = Cpanel::Parallelizer->new( 'process_limit' => $process_limit, 'keep_stdout_open' => 1 );

        my $files_to_download_per_process = $parallelizer->get_operations_per_process( scalar @downloads );

        # Note also that the .sha files that are all downloaded from HTTPUPDATE,
        # so there’s no need to group the files by host.

        my $on_return = sub ($rets) {
            foreach my $download (@$rets) {
                my ( $dest_file, $url, $res ) = @{$download}{qw(dest_file url res)};
                if ( $res->{'status'} ) {
                    $digests{$url} = $res->{'file'};
                }
            }
            return;
        };

        while ( my @download_chunk = splice( @downloads, 0, $files_to_download_per_process ) ) {
            my $urls = join( ',', map { $_->{'download_url'} } @download_chunk );
            $parallelizer->queue(
                sub ( $self, @downloads ) {
                    my @ret;
                    foreach my $download_ref (@downloads) {
                        my $res = $self->download( $download_ref->{'download_url'}, $download_ref->{'dest_file'}, $download_ref->{'opts'} );
                        push @ret, { 'dest_file' => $download_ref->{'dest_file'}, 'url' => $download_ref->{'url'}, 'res' => $res };
                    }
                    return \@ret;
                },
                [ $self, @download_chunk ],
                $on_return,
                sub { warn "Parallelizer error ($urls): @_" },
            );
        }

        $parallelizer->run();
    }

    return \%digests;
}

sub init_digests ( $self, $digest_urls ) {

    die unless $digest_urls;
    my %digests;

    for my $url ( keys %{$digest_urls} ) {
        my $digest_file = $digest_urls->{$url};

        if ( !-e $digest_file ) {

            # If we failed to download the file, skip it.
            # We will check for the existence of the actual digest later.
            next;
        }

        $digests{$url} = { ( map { ( split( /\s+/, $_, 2 ) )[ 1, 0 ] } split( m{\n}, Cpanel::LoadFile::load($digest_file) ) ) };
    }

    return \%digests;
}

sub download_hash ($self) {
    my %download_hash;
    foreach my $package_hash ( $self->install_hash() ) {
        foreach my $package ( keys %{$package_hash} ) {
            my $url          = $self->url( $package, $package_hash->{$package} );
            my $package_file = $self->_get_rpm_name($url);
            my $location     = $self->get_template_name($package);
            $url =~ s/\/$//;
            $url =~ s/\/[^\/]+$//;
            $download_hash{$package_file} = { url => $url, location => $location };
        }
    }

    return \%download_hash;
}

sub download_all ( $self, %opts ) {
    my $temp_dir = $self->{'temp_dir'} or die q[No temp_dir set for download_all];
    -d '/usr/local/cpanel/tmp'         or Cpanel::SafeDir::MK::safemkdir( '/usr/local/cpanel/tmp', '0700', 2 );
    -d $temp_dir                       or Cpanel::SafeDir::MK::safemkdir( $temp_dir,               '0700', 2 );

    my $download_hash = $self->download_hash();

    return [] if !scalar keys %$download_hash;

    my %digest_files;
    my %package_digests;

    for my $alg ( @{ $self->{'digest_algorithms'} } ) {
        $digest_files{$alg}    = $self->stage_digests( $download_hash, $alg, \%opts );
        $package_digests{$alg} = $self->init_digests( $digest_files{$alg} );
    }

    my @packages;

    my @downloads;
    my $process_limit = $opts{'max_sync_children'} ||= $self->calculate_max_sync_children();
    my $parallelizer  = Cpanel::Parallelizer->new( 'process_limit' => $process_limit, 'keep_stdout_open' => 1 );
    my $on_return     = sub (@processed) {
        push @packages, @processed;
        return;
    };

  RPM:
    for my $package_file ( keys %$download_hash ) {

        my $download_to = $temp_dir . '/' . $package_file;
        my %expected_digests;

        my $digest_package_file;
        for my $alg ( @{ $self->{'digest_algorithms'} } ) {

            my $digest_url = $download_hash->{$package_file}->{url};
            $digest_package_file = $package_file;
            if ( $self->is_deb ) {
                $digest_url =~ s{(/pool/)(.+)}{/pool};    # Debian digests are all in one file.
                $digest_package_file = "$2/$digest_package_file";
            }

            my $digest = $package_digests{$alg}->{$digest_url}->{$digest_package_file};

            if ($digest) {
                $expected_digests{$alg} = $digest;
            }
        }

        unless ( keys %expected_digests ) {
            my $err = "No digest data for $digest_package_file";
            $self->logger->fatal($err);
            die $err;
        }

        # Skip if: The file is already downloaded and its digest matches
        if ( -e $download_to ) {
            for my $alg ( @{ $self->{'digest_algorithms'} } ) {
                my $digest = Cpanel::Sync::Digest::digest( $download_to, { algo => $alg } );

                if ( defined($digest) && ( $digest eq $expected_digests{$alg} ) ) {
                    $self->logger->info("$package_file already downloaded") unless $self->{'did_preinstall'};    # Don't say this if we already did a first download pass.
                    push @packages, $package_file;
                    next RPM;
                }
            }
        }

        my $url = $download_hash->{$package_file}->{url} . '/' . $package_file;

        push @downloads, { 'rpm_file' => $package_file, 'url' => $url, 'download_to' => $download_to, 'expected_digests_hr' => \%expected_digests };
    }

    if (@downloads) {
        my $files_to_download_per_process = $parallelizer->get_operations_per_process( scalar @downloads );

        # Note also that the Packages are all downloaded from HTTPUPDATE,
        # so there’s no need to group the Packages by host.
        while ( my @download_chunk = splice( @downloads, 0, $files_to_download_per_process ) ) {
            my $urls = join( ',', map { $_->{'url'} } @download_chunk );
            $parallelizer->queue(
                \&_download_pkgs,
                [ $self, \@download_chunk ],
                $on_return,
                sub { warn "Parallelizer error ($urls): @_" },
            );
        }

        $parallelizer->run();
    }

    return \@packages;
}

sub _download_pkgs ( $self, $packages_ar ) {
    _need_object($self);

    my @complete;
    my $logger = $self->logger();
    foreach my $package (@$packages_ar) {
        my ( $package_file, $url, $download_to, $expected_digests_hr ) = @{$package}{qw(rpm_file url download_to expected_digests_hr)};
        my $err;
      ATTEMPT:
        for my $attempt ( 1 .. $self->{'max_download_attempts'} ) {
            $err = '';
            try {
                my $res = $self->download( $url, $download_to );
                if ( !$res->{'status'} ) {
                    die "Failed to download: $package_file";
                }

                my $success = 0;
                my $digest;
              DIGEST:
                for my $alg ( @{ $self->{'digest_algorithms'} } ) {
                    $digest = Cpanel::Sync::Digest::digest( $download_to, { algo => $alg } );

                    if ( defined($digest) ) {
                        if ( $digest eq $expected_digests_hr->{$alg} ) {
                            $success = 1;
                            last DIGEST;
                        }
                    }
                    else {
                        $logger->warning("Failed to generate local digest for file: $package_file");
                    }
                }
                if ( !$success ) {

                    # We got a file, and none of the checksums match.
                    # Try to download it again.  This clause could
                    # also be reached if we downloaded no checksums,
                    # or we couldn't generate any for the file we did
                    # download.
                    unlink $download_to;

                    my $ip = $self->http_request->{'connectedHostAddress'} || '(unknown)';
                    die "Digest for $url is different from expected (got hash $digest; expected hash $expected_digests_hr->{$self->{'digest_algorithms'}[0]}; mirror IP $ip)";
                }
            }
            catch {
                $err = $_;
            };

            last ATTEMPT if !$err;
            if ( $attempt == $self->{'max_download_attempts'} ) {
                $logger->fatal($err);
                die $err;
            }

            $logger->error( "Retrying download of $package_file (attempt " . ( $attempt + 1 ) . "/$self->{'max_download_attempts'}): $err" );
        }
        push @complete, $package_file;
    }

    $logger->{'brief'} = 1;

    # We only get here if everything succeeded.
    return @complete;
}

sub _get_rpm_name ( $self, $url ) {
    _need_object($self);

    my @url_parts = split /\//, $url;
    my $file      = $url_parts[-1];
    return $file;
}

sub stage ( $self, %opts ) {

    my $packages = $self->download_all(%opts);

    if ( !@$packages ) {
        $self->logger->info("No new Packages needed for install");
    }

    push @{ $self->{'to_install'} }, @{$packages};

    # stage retuns the number of rpms to stage
    # but always returns true on success (0E0 aka Zero but true if there are none to install)
    return scalar @{ $self->{'to_install'} } || '0E0';
}

sub test_rpm_install ( $self, @pkg_files ) {
    _need_object($self);

    $self->{'to_install'} ||= [];

    if ( ( !@pkg_files ) ) {
        @pkg_files = @{ $self->{'to_install'} };
    }

    return 0 unless @pkg_files;

    # This will die if it's something we don't know as an exception.
    $self->pkgr->test_install( $self->{'temp_dir'}, \@pkg_files, $self->uninstall_hash );

    return 1;
}

sub install_rpms ( $self, %options ) {
    _need_object($self);

    my @packages = @{ $self->{'to_install'} || [] };
    return unless @packages;

    my $download_dir = $self->{'temp_dir'};
    -d $download_dir or die("$download_dir unexpectedly missing!");

    my $preinstall = $options{'preinstall'} ? 1 : 0;

    my $errors = $self->pkgr->install( $download_dir, $preinstall, \@packages );

    # No need to do cleanup. This will be done later during the commit_changes call.
    return if $preinstall;

    # If the rpms install successfully, remove *.rpm in the temp dir.
    $self->_cleanup_tmp_packages if !$errors;

    return scalar @packages;
}

sub _cleanup_tmp_packages ($self) {
    _need_object($self);

    my $pkg_ext = $self->pkgr->package_extension;
    unlink( glob( $self->{'temp_dir'} . '/*' . $pkg_ext ) );
    unlink( glob( $self->{'temp_dir'} . '/sha512' ) );

    return;
}

sub uninstall_rpms ( $self, @pkgs ) {
    _need_object($self);

    if ( !@pkgs ) {
        my $pkgs_hash = $self->uninstall_hash() // {};
        @pkgs = keys $pkgs_hash->%*;
    }

    if ( !@pkgs ) {
        $self->logger->info('No packages need to be uninstalled');
        return;
    }
    elsif ( $ENV{'CPANEL_BASE_INSTALL'} ) {
        $self->logger->info('Packages cannot be uninstalled during the base cPanel installation.');
        return;
    }

    return $self->pkgr->uninstall( \@pkgs );    # number of uninstalled packages
}

sub _disable_monitoring_file() {
    return q{/var/run/chkservd.suspend};
}

sub _tailwatchd_was_running_when_rpm_transaction_began() {
    return $_tailwatchd_was_running_when_rpm_transaction_began if defined $_tailwatchd_was_running_when_rpm_transaction_began;
    require Cpanel::Services::Running;
    local $@;

    # If the system is in a very broken state this check will fail.  In this case
    # we want check_cpanel_pkgs to still fix the rpms so we can get things up
    # and going
    eval { $_tailwatchd_was_running_when_rpm_transaction_began = Cpanel::Services::Running::is_online('tailwatchd'); };
    warn if $@;
    return $_tailwatchd_was_running_when_rpm_transaction_began;
}

# Tested directly
sub _restart_monitoring_service_if_running() {
    return if !_tailwatchd_was_running_when_rpm_transaction_began();

    # service can be disabled, hide any errors
    return Cpanel::SafeRun::Errors::saferunnoerror( '/usr/local/cpanel/scripts/restartsrv_tailwatchd', '--no-verbose' );
}

my $monitoring_disabled_from;

# self will not be defined when called from the END block
sub disable_monitoring ( $self = undef ) {
    my $disable_file = _disable_monitoring_file();

    # someone else already disabled it do nothing
    return if -e $disable_file;

    $monitoring_disabled_from = $$;

    if ( ref $self eq __PACKAGE__ ) {
        $self->logger->info("Disabling service monitoring.");
    }

    Cpanel::FileUtils::TouchFile::touchfile($disable_file);
    _restart_monitoring_service_if_running();

    return 1;
}

# self will not be defined when called from the END block
sub restore_monitoring ( $self = undef ) {

    # This subroutine must not modify $? because it is called from an END block.
    local $?;

    return unless $monitoring_disabled_from && $monitoring_disabled_from == $$;

    my $disable_file = _disable_monitoring_file();
    if ( ref $self eq __PACKAGE__ ) {
        $self->logger->info("Restoring service monitoring.");
    }
    Cpanel::FileUtils::Link::safeunlink($disable_file);
    _restart_monitoring_service_if_running();

    # Make sure we unset this or we will restore monitoring
    # again in the END {} block after we already did it
    undef $monitoring_disabled_from;

    return;
}

sub perl_rpm_name {
    return 'cpanel-perl-' . Cpanel::Binaries::PERL_MAJOR();
}

# If the beginning of the line matches this we black list it.

sub preinstall_list ($self) {
    _need_object($self);

    my $perl_rpm_base = perl_rpm_name();

    my $install_hash = $self->install_hash;

    my @list = (
        "$perl_rpm_base-mail-spamassassin",    # Has a big post script that runs perl stuff.
    );

    my $version_sep = Cpanel::OS::is_rpm_based() ? '-' : '_';
    my @pre_install;
    foreach my $package ( keys %$install_hash ) {
        next unless substr( $package, 0, length($perl_rpm_base) ) eq $perl_rpm_base;    # Skip non-perl rpms.
        next if grep { substr( $package, 0, length($_) ) eq $_ } @list;                 # Skip blacklist items.
        next if $package eq $perl_rpm_base;                                             # Skip the main perl rpm (cpanel-perl-536)

        push @pre_install, $package . $version_sep . $install_hash->{$package};
    }

    @pre_install = sort @pre_install;
    return @pre_install;
}

sub perl_package_file_name ( $self, $install_list, $major ) {
    _need_object($self);

    foreach my $pkg (@$install_list) {
        next unless $pkg =~ m/^cpanel-perl-$major[-_]5./;
        return $pkg;
    }
    return;    # couldn't find it.
}

sub clear_installed_packages_cache ($self) {
    $self->pkgr->clear_installed_packages_cache;
    return;
}

sub reset_install_data ($self) {
    _need_object($self);

    # Clear out the object so we forget we installed anything.
    $self->{'to_install'} = [];
    $self->clear_installed_packages_cache;

    # Use stage to re-populate what remains and has not been installed.
    $self->stage();

    return;
}

sub die_if_perl_symlink_is_rpm_owned ($self) {
    _need_object($self);

    my $perl_symlink = $self->{'perl_symlink'} //= '/usr/local/cpanel/3rdparty/bin/perl';

    # The system is unstable when no file is at this path. Sure. But if nothing is there, the risk of the main transaction failing is low so let's proceed.
    return 1 unless ( -l $perl_symlink || -e _ );

    # If there is a directory here, the future rpm transaction will fail.
    if ( -d _ ) {
        die "Stopping upgrade attempt due to $perl_symlink being a directory. cPanel cannot function when this is the case.\n";
    }

    if ( my $owner = $self->pkgr->what_owns($perl_symlink) ) {

        # If we proceed, the main transaction may fail, leaving the system broken. Trow a message to updatenow so it can abort.
        die "Stopping upgrade attempt due to failure to correct the rpm owning $perl_symlink. The following Package may have a problem: $owner";
    }

    # nothing owns the package
    return 2;
}

# This code is for updatenow to be able to pre-install the majority of a new perl version in a way that doesn't interfere with any existing processes.
# This reduces the time of instability between the time that the new binaries are put in place that depend on the new perl and the time when the new
# perl stack is put in place.
#
# This is a total hack. Yes, you should be offended that we did this!

sub preinstall_perlmajor_upgrade ($self) {
    _need_object($self);

    my @original_to_install = @{ $self->{'to_install'} // [] };
    return unless scalar @original_to_install;    # nothing to do

    $self->{'did_preinstall'} = 1;

    # Upgrade the old cpanel-perl-532 so we can remove the 3rdparty/bin symlinks. this will be handled by
    # the cpanel-3rdparty-bin package in the future.
    my $legacy_major = Cpanel::Binaries::PERL_LEGACY_MAJOR();
    my $new_major    = Cpanel::Binaries::PERL_MAJOR();
    $self->logger->info("Updating cpanel-perl-$legacy_major and installing cpanel-perl-$new_major packages prior to switching major versions of perl.");
    $self->{'to_install'} = [];
    foreach my $major ( $legacy_major, $new_major ) {
        my $package = $self->perl_package_file_name( \@original_to_install, $major ) or next;
        push @{ $self->{'to_install'} }, $package;
    }
    eval {
        $self->install_rpms( preinstall => 1 );
        symlink( "/usr/local/cpanel/3rdparty/perl/$legacy_major/bin/perl", "/usr/local/cpanel/3rdparty/bin/perl" );
        $self->logger->info("cpanel-perl-$legacy_major and cpanel-perl-$new_major are now installed.");
    };

    # NOTE: There is a VERY slight chance this upgrade might fail. If /usr/local/cpanel/3rdparty/bin/perl is rpm owned, there is a risk the main transaction will fail horribly.
    # It is better to abort and notify the customer.
    $self->die_if_perl_symlink_is_rpm_owned;

    # Gives back rpms that are in the install_hash that we don't want to preinstall.
    my @preinstall_list = $self->preinstall_list();
    return unless @preinstall_list;

    my @preinstall_files;
    foreach my $package_name (@preinstall_list) {
        my ($package_file) = grep { substr( $_, 0, length($package_name) ) eq $package_name } @original_to_install;
        next unless $package_file;
        push @preinstall_files, $package_file;
    }
    $self->{'to_install'} = \@preinstall_files;

    # Install the modified list of rpms.
    # Ignore failures since we're going to re-run it later.

    my $packages_installed = eval { $self->install_rpms( preinstall => 1 ) };

    # There's a possibiliy a whole bunch of rpms might need to be removed. Lets do this now to reduce the instability window.
    # This is the point where the system is now unstable and we must attempt to move forward with the upgrade no matter what.
    # For instance SA and ClamAV are removed here and exim is potentially unstable until the new exim SA/ClamAV rpms can be put in place.
    $self->uninstall_rpms();

    # Clear everything.
    $self->reset_install_data;

    return !!$packages_installed;
}

sub commit_changes ($self) {
    _need_object($self);
    my @packages = keys $self->install_hash()->%*;

    my $disable = $self->disable_monitoring();
    if ($disable) {    # only when we disabled it
                       # protection when something bad happens
        eval q{ END{ restore_monitoring() } };    ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
    }

    run_hooks( $self->logger(), \@packages, 'pre' );

    my $changes = 0;
    $changes += $self->uninstall_rpms() // 0;
    $changes += $self->install_rpms()   // 0;

    run_hooks( $self->logger(), \@packages, 'post' );

    if ( $self->dir_files()->config_changed() ) {
        $self->dir_files()->save();
    }

    $self->restore_monitoring() if $disable;

    return $changes;
}

sub run_hooks ( $logger, $packages, $stage ) {

    $packages //= [];

    return 0 unless scalar $packages;
    return 0 if $ENV{CPANEL_BASE_INSTALL};

    #YAML::Syck should have already been loaded, but if not,
    #prevent loading incorrect version through the hooks system
    if ( $INC{'YAML/Syck.pm'} ) {
        $logger->info("Hooks system enabled.");
    }
    else {
        $logger->warn("Hooks system unavailable.");
        return 0;
    }

    my $err;
    try {
        require Cpanel::Hooks;

        $logger->info("Checking for and running RPM::Versions '$stage' hooks for any Packages about to be installed");

        foreach my $package ( @{$packages} ) {
            Cpanel::Hooks::hook(
                {
                    'category' => 'RPM::Versions',
                    'event'    => $package,
                    'stage'    => $stage,
                    'blocking' => 1,
                },
            );
        }

        $logger->info("All required '$stage' hooks have been run");
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $logger->warning( "Hooks system failure with Packages ( " . join( ', ', sort @{$packages} ) . " ) " . Cpanel::Exception::get_string($err) );
        return 0;
    }
    return 1;
}

sub get_all_targets_in_state ( $self, $filter ) {
    _need_object($self);

    die unless $filter;

    my $target_settings = $self->target_settings();

    return grep { $target_settings->{$_} eq $filter } keys %{$target_settings};
}

sub save ($self) {
    _need_object($self);

    $self->_clear_cache();
    return $self->dir_files()->save();
}

sub _is_installed_in_os ( $self, $pkg, $version = undef ) {

    my $installed_in_os = $self->pkgr->installed_packages();

    # If a version was passed in, we're yes only if the exact version is installed
    if ( defined $version ) {
        return exists $installed_in_os->{$pkg} && $installed_in_os->{$pkg} eq $version ? 1 : 0;
    }

    # Answer whether the rpm is installed at all.
    return exists $installed_in_os->{$pkg} ? 1 : 0;
}

=over

=item B<get_dirty_rpms>

Returns a hash ref of packages with altered files that looks like:

    {
        'cpanel-some_rpm_name53,5.3.10,5.cp1136'       => [
            ['/path/to/altered/file1','S......T.'],
            ['/path/to/altered/file2','S......T.'],
        ],
        'cpanel-some_other_rpm_name123,1.2.3,1.cp1136' => [
            ['/path/to/file','S......T.'],
            ['/another/path/to/another/file','S......T.'],
        ],
    }

i.e.:

    {
        "$name,$version,$release" => [
            [ $path => $reason ],
            ...
        ],
        ...
    }

NOTE: This output is highly influenced by the local packaging system.

=back

=cut

sub get_dirty_rpms ( $self, $skip_digest_check = 0 ) {
    _need_object($self);

    # Get a list of files altered from original Package install.
    my @cpanel_rpm_list = sort keys %{ $self->list_rpms_in_state('installed') };
    return {} if ( !@cpanel_rpm_list );    # When called with targets, this may be empty;

    return $self->pkgr->get_dirty_packages( \@cpanel_rpm_list, $skip_digest_check );
}

=over

=item B<reinstall_rpms>

Accepts an array of Packages to be removed

=back

=cut

sub reinstall_rpms ( $self, @reinstall ) {
    _need_object($self);

    # Strip version and revision from rpm in list.
    foreach my $package (@reinstall) {
        ($package) = split( ',', $package, 2 );
    }

    $self->pkgr->uninstall_leave_files(@reinstall) if @reinstall;

    $self->stage();
    return $self->commit_changes();
}

=over

=item B<find_from_srpm_sub_packages>

This function returns a hash ref of a package name and version of
for packages that can't be found in the srpm_versions section of
the rpm.versions file but in the srpm_sub_packages.

=back

=cut

sub find_from_srpm_sub_packages ( $self, $name ) {
    _need_object($self);

    my $srpm_sub_package_to_package_map = $self->srpm_sub_package_to_package_map_cached();

    if ( my $key = $srpm_sub_package_to_package_map->{$name} ) {
        my $srpm_versions = $self->srpm_versions_cached();
        my $version_info  = $srpm_versions->{$key};
        if ($version_info) {
            return { $name => $version_info };
        }
    }
    return {};
}

sub url_templates_cached ( $self, $url ) {
    return $self->{'_url_templates'}{$url} ||= $self->url_templates($url);
}

sub srpm_versions_cached ($self) {
    return $self->{'_srpm_versions'} ||= $self->srpm_versions();
}

sub rpm_groups_cached ($self) {
    return $self->{'_rpm_groups'} ||= $self->rpm_groups();
}

sub srpm_sub_packages_cached ($self) {
    return $self->{'_srpm_sub_packages'} ||= $self->srpm_sub_packages();
}

sub rpm_locations_cached ($self) {
    return $self->{'_package_locations'} ||= $self->rpm_locations();
}

sub srpm_sub_package_to_package_map_cached ($self) {
    _need_object($self);
    return $self->{'_srpm_sub_package_to_package_map'} if $self->{'_srpm_sub_package_to_package_map'};
    my $srpm_sub_packages = $self->srpm_sub_packages_cached();
    my %srpm_sub_package_to_package_map;
    foreach my $key ( keys %{$srpm_sub_packages} ) {
        foreach my $srpm_name ( @{ $srpm_sub_packages->{$key} } ) {
            $srpm_sub_package_to_package_map{$srpm_name} = $key;
        }
    }
    return ( $self->{'_srpm_sub_package_to_package_map'} = \%srpm_sub_package_to_package_map );
}

sub _clear_cache ($self) {
    _need_object($self);
    delete @{$self}{qw(_srpm_versions _rpm_groups _srpm_sub_packages _rpm_locations _srpm_sub_package_to_package_map _url_templates)};
    return;
}

1;
