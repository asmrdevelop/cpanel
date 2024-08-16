package Cpanel::BuildState;

# cpanel - Cpanel/BuildState.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::BuildState - query the build environment

=head1 SYNOPSIS

    if ( Cpanel::BuildState::is_development() ) {
        ...
    }

    if ( Cpanel::BuildState::is_nightly_build() ) {
        ...
    }

=head1 DESCRIPTION

This module provides reusable logic to analyze the cPanel & WHM build.

=cut

#----------------------------------------------------------------------

use Cpanel::Version::Full ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_development()

Whether the current environment is development (inclusive of
development sandboxes).

A falsy return from this function indicates a production environment.

=cut

sub is_development {
    return ( ( split m<\.>, _getversion() )[1] % 2 );
}

=head2 $yn = is_nightly_build()

Whether the current build is a nightly build.

=cut

sub is_nightly_build {
    return ( 900 <= ( split m<\.>, _getversion() )[2] ) || 0;
}

#----------------------------------------------------------------------

*_getversion = *Cpanel::Version::Full::getversion;

1;
