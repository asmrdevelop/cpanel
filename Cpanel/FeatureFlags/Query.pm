# cpanel - Cpanel/FeatureFlags/Query.pm            Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::FeatureFlags::Query;

use strict;
use warnings;

use v5.20;
use experimental qw(signatures);
use cpcore;

our $VERSION = '1.0.0';

use Cpanel::FeatureFlags        ();
use Cpanel::FeatureFlags::Cache ();

=head1 MODULE

C<Cpanel::FeatureFlags::Query>

=head1 DESCRIPTION

C<Cpanel::FeatureFlags::Query> provides a set of helper methods related to more complex queries to the
feature flag system.

=head1 SYNOPSIS

=head2 Querying for all the features in a group.

    use Cpanel::FeatureFlags::Query ();
    if (Cpanel::FeatureFlags::Query::has_all_features(qw/feature_a feature_b feature_c/)) {
        # Do the thing that requires all the listed features.
    }

=head2 Querying for at least one in a group.

    use Cpanel::FeatureFlags::Query ();
    if (my $has_any_ftp = Cpanel::FeatureFlags::Query::has_one_of(qw/ftp_pure ftp_pro ftp_xyz/)) {
        # Do the thing that requires at least one ftp feature.
    }

=head2 Querying for one of an exclusive set of a group (A/B testing)

    use Cpanel::FeatureFlags::Query ();

    my @ab_tests = qw/test_a test_b/;
    if (my @has_one_of = Cpanel::FeatureFlags::Query::has_only_one_of(@ab_tests)) {
        # Do the thing that requires one and only of the options
        if ($has_one_of[index(@ab_test, 'test_a')]) {
            # Do thing for the a test.
        } eleif ($has_one_of[index(@ab_test, 'test_b')]) {
            # Do thing for the b test.
        } else {
            # Do nothing...
        }
    }

=head1 FUNCTIONS

=head2 has_all_features(@FEATURES)

Determine if a list of features are enabled for the server.

=head3 ARGUMENTS

=over

=item  @FEATUREs - C<ARRAY of String>

List of unique feature flags to check for on the system.

=back

=head3 RETURNS

C<Boolean>

Boolean representation of existence of all the listed feature flags on the system.

=cut

sub has_all_features (@flag_names) {
    foreach my $flag_name (@flag_names) {
        return 0 if !Cpanel::FeatureFlags::Cache::is_feature_enabled($flag_name);
    }
    return 1;
}

=head2 has_one_of(@FEATURES)

Determine if at least one of the listed features is enabled.

=head3 ARGUMENTS

=over

=item  @FEATUREs - C<ARRAY of String>

List of unique feature flags to check for on the system.

=back

=head3 RETURNS

C<Boolean>

Boolean representation of existence of at least one listed feature flags on the system.

=cut

sub has_one_of (@flag_names) {
    foreach my $flag_name (@flag_names) {
        return 1 if Cpanel::FeatureFlags::Cache::is_feature_enabled($flag_name);
    }
    return 0;
}

=head2 has_only_one_of(@FEATURES)

Determine which one of the listed features is enabled.

=head3 ARGUMENTS

=over

=item  @FEATUREs - C<ARRAY of String>

List of unique feature flags to check for on the system.

=back

=head3 RETURNS

C<ARRAY of Boolean>

List of feature flags that are active on the system. The C<ARRAY> is in the same order the flags were requested in the C<@exclusive_flag_names> argument.

So if we call this with:

  my @checks = has_only_one_of(qw/a b c/);

we get somethine like:

  (
    1, # flag a value
    0, # flag b value
    0, # flag c value
  )

which can then be used to find out which of the flags was enabled

  my ($a_index, $b_index, $c_index) = (0, 1, 2);
  if ($checks[$a_index]) {
    # feature a flag enabled.
  }
  elsif($checks[$b_index]) {
    # feature b flag enabled.
  }
  elsif($checks[$c_index]) {
    # feature c flag enabled.
  }
  else {
    # nothing selected.
  }

=head3 THROWS

When there are multiple features from the exclusive list

=cut

sub has_only_one_of (@exclusive_flag_names) {
    my @acc;
    my $count = 0;
    foreach my $flag_name (@exclusive_flag_names) {
        my $enabled = Cpanel::FeatureFlags::is_feature_enabled($flag_name);
        push @acc, $enabled;
        $count++                                if $enabled;
        die 'Exclusive flags enabled together.' if $count > 1;
    }

    return \@acc;
}

1;
