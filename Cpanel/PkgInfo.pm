package Cpanel::PkgInfo;

# cpanel - Cpanel/PkgInfo.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Reseller ();

our $VERSION = '1.0';

sub PkgInfo_init {
    return 1;
}

sub PkgInfo_planname {
    print _planname();
    return;
}

sub _planname {
    return length $Cpanel::CPDATA{'PLAN'} ? $Cpanel::CPDATA{'PLAN'} : 'undefined';
}

sub _strippedplanname {
    my $pkgname = _planname();

    if ( $pkgname =~ m/_/ ) {
        my ( $reseller, $package ) = split( m/_/, $Cpanel::CPDATA{'PLAN'}, 2 );

        # If a package name is preceded by a reseller’s username and an underscore,
        #	only that reseller can see the package.
        $package = join( '_', $reseller, $package ) if defined $reseller && !Cpanel::Reseller::isreseller($reseller);

        return $package;
    }
    return $pkgname;
}

sub PkgInfo_strippedplanname {
    print _strippedplanname();
    return;
}

1;
