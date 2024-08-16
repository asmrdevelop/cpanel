package Cpanel::Features::Utils;

# cpanel - Cpanel/Features/Utils.pm                Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use cPstrict;
use Cpanel::LoadModule ();

=encoding utf-8

=head1 NAME

Cpanel::Features:Utils

=head1 DESCRIPTION

This is a utility module for checking and parsing feature lists.

=head2 cpuser_data_has_feature($cpuser_data, $feature)

Checks the $cpuser_data as provided by Cpanel::Config::LoadCpUserFile
to see if the provided $feature is enabled.

Returns 1 if the feature is enabled, returns 0 if it is not.

=cut

# $cpuser_data = $_[0]
# $feature = $_[1]
sub cpuser_data_has_feature {
    die 'Invalid cpuser data!'  if !length $_[0];
    die 'Invalid feature name!' if !length $_[1];
    return ( ( $_[0]->{ 'FEATURE-' . ( $_[1] =~ tr[a-z][A-Z]r ) } // '' ) eq '0' ) ? 0 : 1;
}

sub _make_feature_key {
    return 'FEATURE-' . $_[0] =~ tr{a-z}{A-Z}r;
}

1;
