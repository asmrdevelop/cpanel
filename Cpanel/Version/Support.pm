package Cpanel::Version::Support;

# cpanel - Cpanel/Version/Support.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Version::Support

=head1 SYNOPSIS

    if ( version_supports_feature( '11.90.0.2', 'live_transfers' ) ) {
        # ...
    }

=head1 DESCRIPTION

This module exposes logic to determine if a given cPanel & WHM version
supports a specific named feature.

=head1 FEATURES

=over

=item * C<live_transfers>

=back

=cut

#----------------------------------------------------------------------

use Cpanel::Version::Compare ();

my %_feature_version = (
    live_transfers      => '11.89',
    user_live_transfers => '11.95',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $version = get_minimum_version( $FEATURE )

Returns $FEATURE’s minimum-supported version. Throws if
$FEATURE is unrecognized;

=cut

sub get_minimum_version ($feature) {
    return $_feature_version{$feature} || _die_bad_feature($feature);
}

=head2 $yn = version_supports_feature( $VERSION, $FEATURE )

Returns a boolean that indicates whether version $VERSION supports
feature $FEATURE.

=cut

sub version_supports_feature ( $version, $feature ) {
    my $min_version = get_minimum_version($feature);

    return Cpanel::Version::Compare::compare( $version, '>=', $min_version );
}

sub _die_bad_feature ($feature) {
    die "bad feature: “$feature”";
}

1;
