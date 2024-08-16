# cpanel - Cpanel/FeatureFlags/Cache.pm            Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FeatureFlags::Cache;

use strict;
use warnings;

use v5.20;
use experimental qw(signatures);
use cpcore;

our $VERSION = '1.0.0';

=head1 MODULE

C<Cpanel::FeatureFlags::Cache>

=head1 DESCRIPTION

C<Cpanel::FeatureFlags::Cache> provides an in memory pass thru cache of accessed feature flags.

Please use C<Cpanel::FeatureFlags::Cache> instead of C<Cpanel::FeatureFlags> directly.

=head1 SYNOPSIS

  use Cpanel::FeatureFlags::Cache ();
  my $enabled_in_release = Cpanel::FeatureFlags::Cache::is_feature_enabled('app1');
  if ($enabled_in_release) {
    ...
  }

  # Later, use this, but it uses the last value so its a bit more efficent
  $enabled_in_release = Cpanel::FeatureFlags::Cache::is_feature_enabled('app1');
  if ($enabled_in_release) {
    ...
  }

  # If you really want to force a load from disk again first clear the cache.
  Cpanel::FeatureFlags::Cache::clear();

  # And run the check again.
  $enabled_in_release = Cpanel::FeatureFlags::Cache::is_feature_enabled('app1');

  # All Cpanel::FeatureFlags::Cache consumers in this process will now have
  # the updated enablement state.

=cut

my $_cache = {};

=head1 FUNCTIONS

=head2 is_feature_enabled($flag_name)

Checks if the feature is enabled. It first checks the in memory cache then
the underlying C<Cpanel::FeatureFlags> system.

=head3 ARGUMENTS

=over

=item $flag_name - string

The name of a feature flag related to the desired feature.

=back

=cut

sub is_feature_enabled ($flag_name) {
    return $_cache->{$flag_name} if exists $_cache->{$flag_name};

    require Cpanel::FeatureFlags;
    return $_cache->{$flag_name} = Cpanel::FeatureFlags::is_feature_enabled($flag_name);
}

=head2 clear()

Clear the cache manually.

=cut

sub clear() {
    $_cache = {};
    return;
}

1;
