package Whostmgr::Transfers::Version;

# cpanel - Whostmgr/Transfers/Version.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Version::Compare ();

sub servtype_to_version {
    my ($servtype) = @_;

    if ( $servtype =~ m{^WHM([0-9]+)} ) {
        my $numbers = $1;
        my $version;
        if ( length $numbers <= 4 ) {
            $version = substr( $numbers, 0, 2 ) . '.' . substr( $numbers, 2, 2 );
        }
        else {
            $version = substr( $numbers, 0, 2 ) . '.' . substr( $numbers, 2, 2 ) . '.' . substr( $numbers, 4 );
        }
        return $version;
    }
    else {
        return '3.0';
    }
}

# Takes WHM1124, WHM11241, WHM1130 and converts it to a version string
# that can be passed to Cpanel::Version::Compare::compare
sub servtype_version_compare {
    my ( $servtype, $op, $compare_version ) = @_;

    my $version = servtype_to_version($servtype);

    return Cpanel::Version::Compare::compare( $version, $op, $compare_version );
}

1;
