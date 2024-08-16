package Cpanel::Features::Experimental;

# cpanel - Cpanel/Features/Experimental.pm         Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use cpcore;
our $VERSION = '1.0.0';

=encoding utf-8

=head1 NAME

Cpanel::Features::Experimental - Experimental Feature Checking

=head1 SYNOPSIS

    use Cpanel::Features::Experimental;
    my $feature_enabled = Cpanel::Features::Experimental::is_feature_enabled('linked_nodes');
    my $features_updated_at = Cpanel::Features::Experimental::last_modified();

=head1 DEPRECATED

This module is deprecated. Please use C<Cpanel::FeatureFlags> for all new code and if you use
this module, replace its use with C<Cpanel::FeatureFlags>.

=head1 DESCRIPTION

For features that are only available in an experimental fashion, these flags can be used to prevent
unready functionality from being utilized unless explicitly desired.

Example usage:

APIs merge early for detection of side effects caused by the APIs, but end users would have no
benefit from them yet.

=head1 METHODS

=cut

=head2 is_feature_enabled

Determine if an Experimental Feature is enabled

=over 2

=item Input

=over 3

=item C<SCALAR>

$feature_key - unique key representation of the experimental feature

=back

=item Output

=over 3

=item C<SCALAR>

boolean representation of existence of experimental feature

=back

=back

=cut

sub is_feature_enabled {
    my ($feature_key) = @_;

    require Cpanel::Deprecation;
    Cpanel::Deprecation::warn_deprecated_with_replacement( 'Cpanel::Features::Experimental::is_feature_enabled', 'Cpanel::FeatureFlags::is_feature_enabled' );

    require Cpanel::FeatureFlags::Cache;
    return Cpanel::FeatureFlags::Cache::is_feature_enabled($feature_key);
}

=head2 last_modified

Determine when the last change to experimental feature settings occured

=over 2

=item Output

=over 3

=item C<SCALAR>

last modify time in seconds since the epoch

=back

=back

=cut

sub last_modified {
    require Cpanel::Deprecation;
    Cpanel::Deprecation::warn_deprecated_with_replacement( 'Cpanel::Features::Experimental::last_modified', 'Cpanel::FeatureFlags::last_modified' );

    require Cpanel::FeatureFlags;
    return Cpanel::FeatureFlags::last_modified();
}

1;
