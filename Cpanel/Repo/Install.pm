package Cpanel::Repo::Install;

# cpanel - Cpanel/Repo/Install.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception           ();
use Cpanel::Pkgr                ();
use Cpanel::RPM::Versions::File ();
use Cpanel::YAML                ();    # PPI USE OK - Required for run_hooks (do not remove unless removing all calls to run_hooks())
use Cpanel::Database            ();
use Cpanel::OS                  ();
use Cpanel::ArrayFunc::Uniq     ();

use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::Repo::Install

=head1 SYNOPSIS

use parent qw( Cpanel::Repo::Install );

=head1 DESCRIPTION

This module is meant as a base class for subsystems we install via yum or apt.

=head1 FUNCTIONS

=head2 ensure_installer_can_use_repo( SELECTED_VERSION )

This function will install the repo for the current subsystem Install module and check to see
if the selected version of the subsystem is available in that yum or apt repository.

=head3 Arguments

=over 4

=item selected_version    - SCALAR - The version to check that it is in the yum or apt repo.

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

- Selected version not passed
- Failure in verify_package_version_is_available

=cut

sub ensure_installer_can_use_repo {
    my ( $self, $selected_version ) = @_;

    die "ensure_installer_can_use_repo requires a version" if !$selected_version;

    my $repo_name = $self->_repo_name_from_version($selected_version);
    $self->{'output_obj'}->out("Ensuring the “$repo_name” repository is available and working.");

    if ( Cpanel::OS::is_yum_based() ) {
        $self->install_repo($selected_version);
    }
    else {
        my $repo_contents = Cpanel::Database->new( { db_type => $self->{vendor_name}, db_version => $selected_version, reset => 1 } )->get_repo();
        $self->install_repo( $selected_version, $repo_contents );
    }

    $self->{'syspkgs_obj'}->check_and_set_exclude_rules();    # Makes sure is_system_perl_unaltered is in sync
    my $system_perl_is_altered = $self->{'syspkgs_obj'}->is_system_perl_unaltered() ? 0 : 1;

    my $known_deps_hr = $self->_get_known_deps() || {};

    my %deps = (
        ( map { $_ => $selected_version } ( $self->_get_packages_for_target_version($selected_version) ) ),
        %$known_deps_hr,
    );

    my @needed_packages       = sort keys %deps;
    my $installed_versions_hr = Cpanel::Pkgr::installed_packages(@needed_packages);

    # Try to fail before we remove the old mysql/maria rpms.
    foreach my $package (@needed_packages) {
        if ( Cpanel::OS::is_yum_based() ) {
            next if ( $package =~ m{^perl} && $package !~ m{^perl-DBI$} && $system_perl_is_altered );
        }
        else {
            # TODO: Would be nice to move the libdbi-perl packages out of here into a Cpanel::OS question
            next if ( $package =~ m{^libdbi-perl$} );
        }

        if ( $deps{$package} ) {
            $self->{'output_obj'}->out("Ensuring that the package “$package” with version matching “$deps{$package}” is available.");
        }
        else {
            $self->{'output_obj'}->out("Ensuring that the package “$package” is available.");

        }

        if ( $installed_versions_hr->{$package} && !$deps{$package} ) {
            $self->{'output_obj'}->out("The package “$package” version “$installed_versions_hr->{$package}” is already installed.");
            next;
        }
        elsif ( length( $installed_versions_hr->{$package} ) && $installed_versions_hr->{$package} eq $deps{$package} ) {
            $self->{'output_obj'}->out("The package “$package” with version matching “$deps{$package}” is already installed.");
            next;
        }

        try {
            $self->{'syspkgs_obj'}->verify_package_version_is_available(
                'package' => $package,
                'version' => $deps{$package}
            );
        }
        catch {
            die "The system was not able to ensure the availability of the “$package” package: " . Cpanel::Exception::get_string($_);
        };
    }

    $self->{'output_obj'}->out("The “$repo_name” repository is available and working.");
    return 1;
}

=head2 install_known_deps( VERSION )

This function will install the known dependencies for the subsystem Install module, if any are defined.

=head3 Arguments

=over 4

=item version    - SCALAR - The selected version of the software to install the known dependencies for

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

- Error installing dependencies

=cut

sub install_known_deps {
    my ( $self, $version ) = @_;

    my $vendor = $self->{vendor_name};

    $self->{'output_obj'}->out("Installing pre-known $vendor dependencies.");

    my $known_deps_hr = $self->_get_known_deps();
    if ( !$known_deps_hr || !keys %$known_deps_hr ) {
        $self->{'output_obj'}->out("No pre-known $vendor dependencies.");
        return 1;
    }

    my %want_install          = %$known_deps_hr;
    my $installed_versions_hr = Cpanel::Pkgr::installed_packages( keys %want_install );
    my @installed_packages    = grep { $installed_versions_hr->{$_} } keys %$installed_versions_hr;
    delete @want_install{@installed_packages};

    if ( scalar keys %want_install ) {
        try {
            $self->{'syspkgs_obj'}->install_packages(
                'packages'          => [ sort keys %want_install ],
                'excluded_packages' => [ $self->_get_exclude_packages_for_target_version($version) ],
            );
        }
        catch {
            die "Error installing $vendor dependencies: " . Cpanel::Exception::get_string($_);
        };
    }
    $self->{'output_obj'}->out("Installed pre-known $vendor dependencies.");

    return 1;
}

=head2 install_rpms( VERSION )

This function will install the RPMs for the selected version from the installed yum or apt repo.

This function does a dry run first and will abort if it is not successful.

=head3 Arguments

=over 4

=item version    - SCALAR - The selected version to install

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

None directly.

=cut

sub install_rpms {
    my ( $self, $version ) = @_;

    # These all die on failure so the process will stop if anything failed.
    # Bail out here if MariaDB cannot be installed before we remove the MySQL RPMS
    $self->verify_can_be_installed($version);

    return $self->install_pkgs_without_dry_run($version);
}

=head2 install_pkgs_without_dry_run( VERSION )

This function will install the RPMs for the selected version from the installed yum or apt repo.

=head3 Arguments

=over 4

=item version    - SCALAR - The selected version to install

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

None directly.

=cut

sub install_pkgs_without_dry_run {
    my ( $self, $version ) = @_;
    $self->{'vendor_install_obj'}->ensure_rpms() unless $self->{'skip_ensure_rpms'};    # Ensures the compat rpms
    $self->install_repos_and_update($version);

    return 1;
}

=head2 install_repo( TARGET_VERSION )

This function installs the yum or apt repository for the subsystem Install module of the selected version.

=head3 Arguments

=over 4

=item * target_version    - SCALAR - The selected version to install the yum or apt repo for

=item * repo_contents     - String - (Optional) The yum or apt repo file as a string. If this string is passed in, other lookups
will be ignored and this string will be used as the yum or apt repo file. This string should be the entire yum or apt repo file.
It can contain newlines.

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

- If target_version isn't passed

=cut

sub install_repo {
    my ( $self, $target_version, $repo_contents ) = @_;

    die "install_repo requires a version" if !$target_version;

    my $vendor = $self->{vendor_name};

    if ( Cpanel::OS::is_yum_based() ) {
        $self->{'repos_obj'}->install_repo(
            'name'          => $self->_repo_name_from_version($target_version),
            'obsoletes'     => qr/\Q$vendor\E/i,
            'repo_contents' => $repo_contents,
        );    # Dies on failure
    }
    else {
        require Cpanel::PackMan;
        my $pkm = Cpanel::PackMan->instance;
        $pkm->sys->write_repo_conf( $self->{vendor_name}, $repo_contents );
    }

    $self->{'repo_installed'} = 1;
    return 1;
}

=head2 install_repos_and_update( SELECTED_VERSION )

This function installs the yum or apt repo for the selected version of the Install module's subsystem and
then installs that version.

=head3 Arguments

=over 4

=item selected_version    - SCALAR - The selected version to install the yum or apt repo for and then install

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

- If selected_version isn't passed

=cut

sub install_repos_and_update {
    my ( $self, $selected_version ) = @_;

    die "install_repos_and_update requires a version" if !$selected_version;

    $self->_display_and_install_repo($selected_version);

    Cpanel::RPM::Versions::File::run_hooks( $self->{'output_obj'}, [ $self->_get_packages_for_target_version($selected_version) ], 'pre' );    # Failure is not fatal

    if ( $self->{'vendor_install_obj'}->can('NO_DEPS_PRE_UNINSTALLS') ) {
        my @no_deps_uninstalls = $self->{'vendor_install_obj'}->NO_DEPS_PRE_UNINSTALLS();
        if (@no_deps_uninstalls) {
            $self->_uninstall_pkg_providees_nodeps(@no_deps_uninstalls);
        }
    }

    $self->_uninstall_incompatible_packages($selected_version);

    # _uninstall_other_version_packages_if_needed dies on failure
    $self->_uninstall_other_version_packages_if_needed($selected_version);

    # install_packages dies on failure
    $self->{'syspkgs_obj'}->install_packages( $self->_get_args_for_syspkgs($selected_version) );

    my $vendor = $self->{vendor_name};
    $self->{'output_obj'}->out("$vendor installed from official repository.");

    $self->_call_before_final_hooks();

    Cpanel::RPM::Versions::File::run_hooks( $self->{'output_obj'}, [ $self->_get_packages_for_target_version($selected_version) ], 'post' );    # Failure is not fatal

    # ensure_rpms dies on failure
    $self->{'vendor_install_obj'}->ensure_rpms() unless $self->{'skip_ensure_rpms'};

    return 1;
}

sub _display_and_install_repo {
    my ( $self, $selected_version ) = @_;

    return if $self->{'repo_installed'};

    my $vendor = $self->{vendor_name};

    $self->{'output_obj'}->out("Installing $vendor from official repository.");

    $self->install_repo($selected_version);

    return;
}

sub _get_args_for_syspkgs {
    my ( $self, $selected_version ) = @_;

    return (
        'packages'         => [ $self->_get_packages_for_target_version($selected_version) ],
        'exclude_packages' => [ $self->_get_exclude_packages_for_target_version($selected_version) ],

    );
}

sub download_pkgs {
    my ( $self, $selected_version ) = @_;

    die "download_pkgs requires a version" if !$selected_version;

    $self->_display_and_install_repo($selected_version);

    # download_packages dies on failure
    $self->{'syspkgs_obj'}->download_packages( $self->_get_args_for_syspkgs($selected_version) );

    return 1;

}

# Override in subclasses to call other commands before the final hooks are run
sub _call_before_final_hooks {
    my ($self) = @_;

    return;
}

#tested directly
sub _uninstall_pkg_providees_nodeps {
    my ( $self, @providees_to_uninstall ) = @_;

    $self->{'output_obj'}->out("Looking for providers that will cause dependency problems: @providees_to_uninstall");

    # CPANEL-38934: This needs to load Cpanel::ArrayFunc::Uniq directly; trying to call uniq via typeglob-aliased Cpanel::ArrayFunc::uniq caused MySQL upgrades to fail in WHM
    my @packages_to_uninstall = Cpanel::ArrayFunc::Uniq::uniq( map { split m<\n+>, Cpanel::Pkgr::what_provides($_) // '' } @providees_to_uninstall );

    if (@packages_to_uninstall) {

        # YAGNI: if we need to take different actions for removing 'rpms that cause dependency problems'
        # compared to the actions we take when removing 'incompatible packages' then this will need to be
        # refactored and a new "hook" point will need to be introduced.
        #
        # As of now, the actions are the same, so keeping this simple and just calling the existing hook.
        $self->_call_before_uninstall_incompatible_packages();

        my $package_manager = Cpanel::OS::package_manager();
        my $low_level_tool  = $package_manager eq 'apt' ? 'dpkg' : 'rpm';
        $self->{'output_obj'}->out("Uninstalling the following via “$low_level_tool” prior to “$package_manager” to avoid dependency problems: @packages_to_uninstall");

        Cpanel::Pkgr::remove_packages_nodeps(@packages_to_uninstall);

        $self->_call_after_uninstall_incompatible_packages();
    }
    else {
        $self->{'output_obj'}->out("There are no installed packages that cause known dependency problems");
    }
    return;
}

=head2 verify_can_be_installed( VERSION )

This function checks to see if packages from the subsystem Install module can install or dies.

=head3 Arguments

=over 4

=item version    - SCALAR - The version to verify if the packages will install for

=back

=head3 Returns

This function either returns 1 on success or dies.

=head3 Exceptions

- If the version isn't passed.
- If any of the packages cant be installed

=cut

sub verify_can_be_installed {
    my ( $self, $version, $opts_hr ) = @_;

    die "verify_can_be_installed requires a version" if !$version;

    my $vendor = $self->{vendor_name};

    $self->{'output_obj'}->out("Verifying that the $vendor packages can be installed by doing a test install.");
    my $targets_regex = join(
        '|',
        map { quotemeta($_) } $self->_get_pkg_targets()
    );

    $self->{'syspkgs_obj'}->check_and_set_exclude_rules();    # Makes sure is_system_perl_unaltered is in sync

    # can_packages_be_installed dies on failure
    my $can_be_installed = $self->{'syspkgs_obj'}->can_packages_be_installed(
        'packages'                        => [ $self->_get_packages_for_target_version($version) ],
        'exclude_packages'                => [ $self->_get_exclude_packages_for_target_version($version) ],
        'ignore_conflict_packages_regexp' => qr/(?:$targets_regex)/,
        ( ( $opts_hr && exists $opts_hr->{'check_yum_preinstall_stderr'} ) ? ( 'check_yum_preinstall_stderr' => $opts_hr->{'check_yum_preinstall_stderr'} ) : () ),
    );

    if ( !$can_be_installed ) {
        my $system_perl_is_altered = $self->{'syspkgs_obj'}->is_system_perl_unaltered() ? 0 : 1;
        if ($system_perl_is_altered) {
            die "The preinstall check failed. The install may have failed because system perl has been altered. $vendor cannot be installed.";
        }
        else {
            die "The preinstall check failed. $vendor cannot be installed.";
        }
    }

    $self->{'output_obj'}->out("Preinstall check passed.");

    return 1;
}

sub _get_pkg_targets {
    die "Overriding _get_pkg_targets is required!";
}

sub _get_incompatible_packages {
    return;
}

sub _get_known_deps {
    return;
}

sub _get_versions_to_remove {
    return;
}

sub _repo_name_from_version {
    my ( $self, $target_version ) = @_;

    my $vendor = $self->{vendor_name};

    die "Invalid $vendor version: “$target_version."
      if $target_version !~ m{^[0-9]+\.[0-9]+$};

    my $full_version = $target_version;

    $full_version =~ s/\.//g;

    return "$vendor" . $full_version;
}

sub _call_before_uninstall_incompatible_packages {
    return;
}

sub _uninstall_incompatible_packages {
    my ( $self, $selected_version ) = @_;
    my $incompatible_packages = $self->_get_incompatible_packages($selected_version);

    if ( Cpanel::OS::is_apt_based() ) {
        return 1 if !$incompatible_packages;
    }

    if ( defined $incompatible_packages ) {
        $self->{'output_obj'}->out("Removing any of the following incompatible packages: @$incompatible_packages");
    }

    $self->_call_before_uninstall_incompatible_packages();
    my $current_versions = Cpanel::Pkgr::installed_packages(@$incompatible_packages);    # dies on failure
    foreach my $package (@$incompatible_packages) {
        my $current_version = $current_versions->{$package};
        if ( !$current_version ) {
            next;                                                                        # not installed
        }
        $self->{'output_obj'}->out("Removing the currently installed version of $package ($current_version) as it is not compatible.");

        # uninstall_packages will die on failure
        $self->{'syspkgs_obj'}->uninstall_packages( 'packages' => ["$package-$current_version"] );
    }
    $self->_call_after_uninstall_incompatible_packages();

    return 1;
}

sub _call_after_uninstall_incompatible_packages {
    return;
}

sub _uninstall_other_version_packages_if_needed {
    my ( $self, $selected_version ) = @_;

    my $versions_to_remove = $self->_get_versions_to_remove();

    if ( $versions_to_remove && @$versions_to_remove ) {
        my $installed_versions_hr = Cpanel::Pkgr::installed_packages(@$versions_to_remove);
        foreach my $package ( sort keys %$installed_versions_hr ) {
            my $current_version = $installed_versions_hr->{$package};
            if ( !$current_version ) {
                next;    # not installed
            }
            elsif ( $current_version !~ m{^\Q$selected_version\E} ) {
                $self->{'output_obj'}->out("Removing the currently installed version of $package ($current_version) in order to prepare for $package ($selected_version).");

                # uninstall_packages will die on failure
                $self->{'syspkgs_obj'}->uninstall_packages( 'packages' => ["$package-$current_version"] );
            }
        }
    }

    return 1;
}

1;
