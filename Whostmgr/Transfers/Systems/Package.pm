package Whostmgr::Transfers::Systems::Package;

# cpanel - Whostmgr/Transfers/Systems/Package.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# RR Audit: JNK

use Try::Tiny;
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Exception              ();
use Whostmgr::Packages::Load       ();
use Whostmgr::Packages::Restore    ();

use base qw(
  Whostmgr::Transfers::Systems
);

sub get_phase {
    return 10;
}

sub get_prereq {
    return ['CpUser'];
}

# Note: there is no restricted restore method for this module

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This recreates account packages.') ];
}

sub get_restricted_available {
    return 0;
}

sub get_notes {
    my ($self) = @_;
    return [ $self->_locale()->maketext('If the target server does not have the package that the user has been assigned, the system will use the account’s properties to recreate the package.') ];
}

sub restricted_restore {
    my ($self) = @_;

    my $user        = $self->newuser();
    my $cpuser_data = Cpanel::Config::LoadCpUserFile::load($user);
    my $plan        = $cpuser_data->{'PLAN'} || 'undefined';
    return ( 1, 'The package is not set.' ) if $plan eq 'undefined';

    if ( !$self->_package_exists($plan) ) {
        return ( $Whostmgr::Transfers::Systems::UNSUPPORTED_ACTION, $self->_locale()->maketext( 'Restricted restorations do not use the “[_1]” module.', 'Package' ) );
    }

    return 1;
}

sub unrestricted_restore {
    my ($self) = @_;

    my $user = $self->newuser();

    my $cpuser_data = Cpanel::Config::LoadCpUserFile::load($user);

    my $plan = $cpuser_data->{'PLAN'} || 'undefined';
    return ( 1, 'The package is not set.' ) if $plan eq 'undefined';

    # The package name was already validated in Whostmgr::Transfers::ArchiveManager::Validate
    # if this is a new account. So, we do not need to validate the package name here.
    if ( $self->_package_exists($plan) ) {
        return ( 1, 'The package exists on the system.' );
    }

    my $error_obj;
    try {
        Whostmgr::Packages::Restore::create_package_from_cpuser_data($cpuser_data);
    }
    catch {
        $error_obj = $_;
    };

    if ($error_obj) {

        # The package may already exist due a TOCTOU race condition with multiple account restores that have the
        # same package that needs to be recreated.
        if ( !UNIVERSAL::isa( $error_obj, 'Cpanel::Exception::HostingPackage::AlreadyExists' ) ) {
            my $setting_default_error_obj;
            try {
                $self->_set_cpuser_keys_to_default( $user, [ 'PLAN', 'FEATURELIST' ] );
            }
            catch {
                $setting_default_error_obj = $_;
            };

            if ($setting_default_error_obj) {
                return ( 0, Cpanel::Exception::get_string($setting_default_error_obj) );
            }

            $self->warn( $self->_locale()->maketext( 'The package and feature list settings for the user “[_1]” have been set to [output,asis,default] because the package “[_2]” does not exist on the system and could not be recreated due to an error: [_3]', $user, $plan, Cpanel::Exception::get_string($error_obj) ) );
            return ( 1, 'Package and feature list set to default.' );
        }
    }

    return ( 1, 'Package restored.' );
}

sub _package_exists {
    my ( $self, $pkg ) = @_;

    return 0 if index( $pkg, '/' ) != -1;

    return 1 if $pkg eq 'default';

    return -e ( Whostmgr::Packages::Load::package_dir() . $pkg ) ? 1 : 0;

}

1;
