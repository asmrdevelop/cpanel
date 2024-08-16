package Whostmgr::Cpaddon;

# cpanel - Whostmgr/Cpaddon.pm                      Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Logger                  ();
use Cpanel::Locale                  ();
use Cpanel::Output::Formatted::HTML ();
use Cpanel::Version::Compare        ();
use Cpanel::SysPkgs                 ();
use Cpanel::Pkgr                    ();
use Cpanel::RepoQuery               ();

=head1 NAME

Whostmgr::Cpaddon;

=head1 SYNOPSIS

  use Whostmgr::Cpaddon ();
  my $available = Whostmgr::Cpaddon::get_available_addons();

=head1 DESCRIPTION

Packaging support and integration points for the cPAddons WHM UI.

=head1 FUNCTIONS

=head2 get_available_addons()

=head3 Description

List all the available packages which provide a cPAddon.

=head3 Arguments

No Arguments

=head3 Returns

This function returns a hash ref, containing a structured key that follows the
format "vendor::category::name" and is retrieve from the package specs description
field in the Namespace: <full namespace name>. The value of this element
is a hash ref containing the pre-install details for the cpaddon. This data is
used to drive the Whostmgr UI and logic.

=over

=item - VERSION - String - The package version number for the item.

=item - version - String - The version number of the item, which should correspond to the version number of the item being installed.

=item - package - HashRef - Containing the package information

=over

=item - release - String - The version number of the release. This corresponds to the packages version number.

=item - rpm_name - String - The name of the package that provides this cPAddon

=item - is_rpm - Boolean - Always true

=item - description - String - The description from the package spec.

=item - summary - String - The summary line from the package spec.

=back

=item - namespace - String - Perl module that manages the cPAddon meta-data.

=item - categories - ArrayRef - List of categories the add supports. The first category is the primary category.

=item - application - HashRef - Containing the application properties:

=over

=item - name - String - Display name of the primary application managed in the package.

=item - summary - String - Display summary of the primary application managed in the package.

=back

=back

=cut

sub get_available_addons {
    my $available = {};

    my $cpaddon_packages = Cpanel::RepoQuery::what_provides('cPanel-cPAddon');

    for my $package (@$cpaddon_packages) {
        my ( $description, $meta ) = _separate_description_and_metadata( $package->{'description'} );

        my $application          = $meta->{Application} || undef;
        my $categories           = $meta->{Categories}  || [];
        my $namespace            = $meta->{Namespace}   || undef;
        my $application_summary  = $meta->{Summary}     || undef;
        my $distribution_version = join '-', @$package{qw(version release)};

        my $addon = {
            VERSION => $distribution_version,
            version => $package->{'version'},
            package => {
                release     => $package->{'release'},
                rpm_name    => $package->{'name'},
                is_rpm      => 1,
                description => $description,
                summary     => $package->{'summary'},
            },
            namespace   => $namespace,
            categories  => $categories,
            application => {
                name    => $application,
                summary => $application_summary,
            },
        };

        next if !_validate_addon($addon);

        # Check if the YUM repo has a newer version
        # of the same package cPAddon so we only list the latest
        next
          if $available->{$namespace}
          and _compare_addon_versions( $available->{$namespace}, $addon );

        $available->{$namespace} = $addon;
    }

    return $available;
}

=head2 has_some_addons_installed()

=head3 Description

Check if the server has some cPaddon installed.

=head3 Arguments

No Arguments

=head3 Returns

Returns a boolean:

- true: when one or more addons installed.
- false: when no addons are installed

=cut

sub has_some_addons_installed() {

    my $count = scalar keys get_installed_addons()->%*;

    return !!$count;
}

=head2 get_installed_addons()

=head3 Description

List all the installed package packages which provide a cPAddon.

=head3 Arguments

No Arguments

=head3 Returns

This function returns a hash ref, containing a structured key that follows the
format "vendor::category::name" and is retrieve from the package specs description
field in the Namespace: <full namespace name>. The value of this element
is a hash ref containing the installed details for the cpaddon. The data is extracted
from the package spec, not from the package contents. This data is used to drive the Whostmgr
UI and logic.

=over

=item - VERSION - String - The package version number for the item.

=item - version - String - The version number of the item, which should correspond to the version number of the item being installed.

=item - package - HashRef - Containing the package information

=over

=item - release - String - The version number of the release. This corresponds to the packages version number.

=item - rpm_name - String - The name of the package that provides this cPAddon

=item - is_rpm - Boolean - Always true

=item - description - String - The description from the package spec.

=item - summary - String - The summary line from the package spec.

=back

=item - namespace - String - Perl module that manages the cPAddon meta-data.

=item - categories - ArrayRef - List of categories the add supports. The first category is the primary category.

=item - application - HashRef - Containing the application properties:

=over

=item - name - String - Display name of the primary application managed in the package.

=item - summary - String - Display summary of the primary application managed in the package.

=back

=back

=cut

sub get_installed_addons {
    my $installed = {};

    my $cpaddon_packages = Cpanel::Pkgr::what_provides_with_details('cPanel-cPAddon');

    for my $package (@$cpaddon_packages) {

        my ( $description, $meta ) = _separate_description_and_metadata( $package->{'description'} );

        my $application          = $meta->{Application} || undef;
        my $categories           = $meta->{Categories}  || [];
        my $namespace            = $meta->{Namespace}   || undef;
        my $application_summary  = $meta->{Summary}     || undef;
        my $distribution_version = join '-', @$package{qw(version release)};

        my $addon = {
            VERSION => $distribution_version,
            version => $package->{'version'},
            package => {
                release     => $package->{'release'},
                rpm_name    => $package->{'name'},
                is_rpm      => 1,
                description => $description,
                summary     => $package->{'summary'},
            },
            namespace   => $namespace,
            categories  => $categories,
            application => {
                name    => $application,
                summary => $application_summary,
            },
        };

        next if !_validate_addon($addon);

        # Check if the YUM repo has a newer version
        # of the same package cPAddon so we only list the latest
        next
          if $installed->{$namespace}
          and _compare_addon_versions( $installed->{$namespace}, $addon );

        $installed->{$namespace} = $addon;
    }
    return $installed;
}

sub _compare_addon_versions {
    my ( $addon1, $addon2 ) = @_;

    # Check the app version first
    my $app_version_greater = Cpanel::Version::Compare::compare( $addon1->{version} || 0, '>', $addon2->{version} || 0 );
    return 1 if $app_version_greater;

    # Otherwise check if its a newer packaging of the same version of the app.
    my $app_version_equal       = Cpanel::Version::Compare::compare( $addon1->{version}          || 0, '==', $addon2->{version}          || 0 );
    my $package_version_greater = Cpanel::Version::Compare::compare( $addon1->{package}{release} || 0, '>',  $addon2->{package}{release} || 0 );
    return ( $app_version_equal && $package_version_greater );
}

sub _parse_meta {
    my ( $meta, $transforms ) = @_;
    my @lines = split "\n", $meta;

    my $section;
    my %meta = ( sections => [] );
    for my $line (@lines) {
        chomp $line;
        next if $line =~ m/^[#]/;           # skips comments
        $line =~ s/^\s+|\s+$//g;            # remove leading/trailing whitespace
        next if !$line;                     # skip empty lines

        # Look for section headers
        if ( $line =~ m/^\[([^]]*)\]$/ ) {

            # section identifier
            $section = $1;
            push @{ $meta{sections} }, {};
        }
        elsif ( $line =~ m/^[^:]*:.*$/ ) {

            # property in current section
            my ( $key, $val ) = split /:/, $line, 2;    #splits the line on the first :
            $val =~ s/^\s+|\s+$//g;                     # remove leading/trailing whitespace
            if ( my $transform = $transforms->{$key} ) {
                $val = $transform->($val);
            }

            if ( $section && $key ) {
                $meta{sections}[-1]{$key} = $val;
            }
            elsif ($key) {
                $meta{$key} = $val;
            }
        }
        else {
            die "$line is malformed for the metadata format";
        }
    }
    return \%meta;
}

sub _parse_delimited_to_array_ref {
    my ( $value, $delimiter ) = @_;
    my @parts = map {
        my $tmp = $_;
        $tmp =~ s/^\s+|\s+$//g;
        $tmp;
    } split( m/$delimiter/, $value );
    return \@parts if @parts;
    return undef;
}

sub _separate_description_and_metadata {
    my $description = shift;
    my @parts       = split( /--- cPAddon Metadata ---/, $description );
    my $meta        = _parse_meta(
        $parts[1],
        {
            Categories => sub {
                return _parse_delimited_to_array_ref( $_[0], qr/,/ );
            },
            Supported => sub {
                return _parse_delimited_to_array_ref( $_[0], qr/\s+/ );
            },
        }
    ) if @parts > 1;
    return ( $parts[0], $meta );
}

sub _validate_addon {
    my $addon = shift;

    my $ok = 1;
    my @problems;
    if ( !$addon->{namespace} ) {
        push @problems, 'The required metadata namespace property is missing.';
        $ok = 0;
    }

    if ( !$addon->{application}{name} ) {
        push @problems, 'The required metadata application property is missing.';
        $ok = 0;
    }

    if ( !$addon->{application}{summary} ) {
        push @problems, 'The required metadata summary property is missing.';
        $ok = 0;
    }

    if ( !$addon->{categories} ) {
        push @problems, 'The required categories property is missing or malformed.';
        $ok = 0;
    }

    if ( !$ok ) {
        _logger()->warn( "The cPAddon in $addon->{package}{rpm_name} $addon->{VERSION} is missing required meta-data:\n" . join( "\n", @problems ) );
    }

    return $ok;
}

my $logger;

sub _logger {
    $logger = Cpanel::Logger->new();
    return $logger;
}

=head2 install_addon(packageNAME, ...)

=head3 Description

Installs one or more package-based cPAddons from the list available to be deployed by cPanel end-users.

=head3 Arguments

=over

=item * packageNAME - String - The name of the package package to be installed.

=item * ... - Additional arguments of the same form may be supplied to install multiple addons at once.

=back

=head3 Returns

True on success, False on failure.

=cut

sub install_addon {
    my @package_names = @_;

    die "DEVELOPER ERROR: Must provide at least 1 package name to install_addon() method." if !@package_names;

    my $addons = _get_best_addons();
    my @install_packages;
    for my $package_name (@package_names) {
        if ( my $package = $addons->{$package_name} ) {
            my ( $description, $meta ) = _separate_description_and_metadata( $package->{'description'} );

            my @prerequisites = _calculate_variable_prerequisites($meta);
            push @install_packages, @prerequisites if @prerequisites;
        }
        push @install_packages, $package_name;
    }

    my $yum = Cpanel::SysPkgs->new();
    return $yum->install(
        packages        => \@install_packages,
        disable_plugins => ['fastestmirror'],
    );
}

=head2 _get_best_addons()

Returns a list of the best version of all the available cpaddons.

=head3 RETURNS

HASH REF where the names are the cpaddon package name and the values are the raw package metadata.

=cut

sub _get_best_addons {

    my %best;
    my %ret;
    my $all_addons = Cpanel::RepoQuery::what_provides('cPanel-cPAddon');

    for my $package (@$all_addons) {
        my $name  = $package->{name};
        my $addon = {
            version => $package->{version},
            package => {
                release => $package->{release},
            },
        };

        # Check if the YUM repo has a newer version
        # of the same package cPAddon so we only list the latest
        next
          if $best{$name}
          and _compare_addon_versions( $best{$name}, $addon );

        $best{$name} = $addon;
        $ret{$name}  = $package;
    }

    return \%ret;
}

# Calculate the additional prerequisites from the Requires-Vary-By-Version:
# sections in the meta data for the package. This system may be replaced with
# pure package solutions once our package version has conditional constructs so
# the Requires: can contain or and if checks.
sub _calculate_variable_prerequisites {
    my $meta = shift;
    my @prerequisites;

    my $output = Cpanel::Output::Formatted::HTML->new();

    my $yum = Cpanel::SysPkgs->new();
    foreach my $section ( @{ $meta->{sections} } ) {
        my @supported = @{ $section->{"Supported"} };
        my $preferred = $section->{"Preferred"};

        $output->out("Building version dependent dependencies.\n");

        my $found = 0;
        foreach my $optional_package (@supported) {
            $output->out("\nChecking for optional dependency: $optional_package\n");

            my $version = Cpanel::Pkgr::get_package_version($optional_package);
            if ( length $version ) {
                $output->increase_indent_level();
                $output->out("Found package ${optional_package}=${version}\n");
                $output->decrease_indent_level();

                # Add the dependencies for the already
                # installed option if any are listed.
                if ( my $prerequisite = $section->{$optional_package} ) {
                    $output->out(" * $optional_package: adding $prerequisite as a dependency\n");
                    push @prerequisites, $prerequisite;
                }
                $found = 1;
                last;
            }
        }

        if ( !$found && $preferred ) {
            $output->out("\n\n");
            $output->warn("Could not find any of the optional dependencies on your system.\n");
            $output->out("Installing the preferred optional dependency: $preferred\n");

            # We did not see any of the environments we expected so
            # we install the preferred prerequisite
            push @prerequisites, $preferred;

            # And its dependencies if any.
            if ( my $prerequisite = $section->{$preferred} ) {
                $output->out(" * $preferred: adding $prerequisite as a dependency\n");
                push @prerequisites, $prerequisite;
            }
        }
        elsif ( !$found ) {
            my $locale = Cpanel::Locale->get_handle();

            $output->out("\n\n");
            die $locale->maketext( "You must install one the following dependencies: [list_or,_1]", \@supported ) . "\n";
        }

        $output->out("\n\n");
    }

    return @prerequisites;
}

=head2 erase_addon(packageNAME, ...)

=head3 Description

Removes an package-based cPAddon from the list available to be deployed by cPanel end-users.
Existing deployments will be left intact.

=head3 Arguments

=over

=item * packageNAME - String - The name of the package to be removed.

=item * ... - Additional arguments of the same form may be supplied to uninstall multiple addons at once.

=back

=head3 Returns

True on success.

Otherwise, an exception will be thrown.

=cut

sub erase_addon {
    my @package_names = @_;
    require Cpanel::SysPkgs;
    my $yum = Cpanel::SysPkgs->new();
    return $yum->uninstall_packages(
        packages        => \@package_names,
        disable_plugins => ['fastestmirror']
    );    # throws an exception on failure
}

1;
