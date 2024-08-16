package Whostmgr::Resellers::Pkg;

# cpanel - Whostmgr/Resellers/Pkg.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Limits::PackageLimits ();
use Whostmgr::Limits::Resellers     ();

sub add_pkg_permission {
    my $user     = shift;
    my $pkg_name = shift;

    my $reseller_limits = Whostmgr::Limits::Resellers::load_resellers_limits();

    if ( $reseller_limits->{'limits'}->{'preassigned_packages'}->{'enabled'} ) { return; }    #do not auto grant the permission

    {
        my $package_limits = Whostmgr::Limits::PackageLimits->load(1);
        $package_limits->create_for_reseller( $pkg_name, $user, 1 );
        $package_limits->save();
    }
    return;
}

1;
