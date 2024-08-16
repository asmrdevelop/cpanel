package Whostmgr::Packages::Restore;

# cpanel - Whostmgr/Packages/Restore.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception       ();
use Cpanel::Features::Load  ();
use Whostmgr::Packages::Mod ();

###########################################################################
#
# Method:
#   create_package_from_cpuser_data
#
# Description:
#   This function is an exception producing wrapper around _addpkg
#   and ultimately _modpkg. It relies on convert_cpuser_to_package_keys to do
#   its key conversion. We needed a way to detect if the package creation failed
#   only due to a package already existing, so this method was created to keep the parsing
#   of the error message close to the error message itself. That way if one is edited, it
#   wouldn't be too far to search for the other.
#
# Parameters:
#   $package_name   - The name of the package to create from CPUSER data.
#   $cpuser_data_hr - A hashref representing the CPUSER data for a user. The package settings
#      will be derived from this data.
#
# Exceptions:
#   Cpanel::Exception::AttributeNotSet               - Thrown if PLAN is not included in the CPUSER data.
#   Cpanel::Exception::HostingPackage::AlreadyExists - Thrown if the package already exists.
#   Cpanel::Exception::HostingPackage::CreationError - Thrown if there is a generic error with
#      the creation of the package.
#
# Returns:
#   The method returns 1 on success or an exception if it failed.
#
sub create_package_from_cpuser_data {
    my ($cpuser_data_hr) = @_;

    if ( !$cpuser_data_hr->{'PLAN'} ) {
        die Cpanel::Exception::create( 'AttributeNotSet', 'The parameter “[_1]” must contain the attribute “[_2]”.', [ 'cpuser_data_hr', 'PLAN' ] );
    }

    my %new_package = %{$cpuser_data_hr};

    if ( exists $new_package{'FEATURELIST'} && !Cpanel::Features::Load::is_feature_list( $new_package{'FEATURELIST'} ) ) {
        $new_package{'FEATURELIST'} = 'default';
    }

    $new_package{'name'} = $new_package{'PLAN'};

    if ( $new_package{'BWLIMIT'} eq '0' ) {
        $new_package{'BWLIMIT'} = 'unlimited';
    }

    my ( $status, $message, %package_or_failure ) = Whostmgr::Packages::Mod::_addpkg(%new_package);

    ####################################################################
    #
    # This is not a good way to check for specific failures.
    # Unfortunately, Whostmgr::Packages::Mod::_addpkg() does not throw exceptions
    # so to get the reason for failure, we need to parse the failure reason we passed back.
    #

    if ( !$status ) {
        if ( defined $package_or_failure{'exception_obj'} && UNIVERSAL::isa( $package_or_failure{'exception_obj'}, 'Cpanel::Exception::HostingPackage::AlreadyExists' ) ) {
            die $package_or_failure{'exception_obj'};
        }
        else {
            die Cpanel::Exception::create( 'HostingPackage::CreationError', [ 'package_name' => $cpuser_data_hr->{'PLAN'}, 'error' => $message ] );
        }
    }

    #
    # Please do not repeat this unless it is absolutely necessary.
    #
    ####################################################################

    return 1;
}

1;
