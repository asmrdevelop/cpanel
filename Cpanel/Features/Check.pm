package Cpanel::Features::Check;

# cpanel - Cpanel/Features/Check.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Features::Cpanel       ();
use Cpanel::Features::Utils        ();
use Cpanel::Config::LoadCpUserFile ();
use Cpanel::AcctUtils::Lookup      ();

=encoding utf-8

=head1 NAME

Cpanel::Features::Check

=head1 DESCRIPTION

This module allows you to check the features a user does and doesn't have access to.

This module is not intended to be called in user context and should only be used
as root.

=head1 FUNCTIONS

=head2 check_feature_for_user( USER, FEATURE_NAME, FEATURE_LIST, CPUSER_DATA_HR )

Checks whether the provided system user, or system user that owns the provided webmail user,
has access to the feature in question.

=head3 Arguments

- USER - String - The cPanel user to check. This can be Webmail user, but the check will
                  be run on the system user that owns the mail user.

- FEATURE_NAME - String - The name of the feature to check for.

- FEATURE_LIST - String (optional) - The name of the feature list to use when performing the
check. If not given, this value is looked up from the FEATURELIST setting in the system user's
cp user file.

- CPUSER_DATA_HR - Hashref (optional) - The hashref returned from
Cpanel::Config::LoadCpUserFile::load*

=head3 Returns

Returns true if the cPanel user has access to the feature and false if it doesn't.

=cut

# TODO: check_feature_for_user has grown to allow passing
# $cpuser_data, however if we have $feature_list we likely
# have $cpuser_data.  We should refactor this in the future
# to take $cpuser_data only.
sub check_feature_for_user {
    my ( $user, $feature_name, $feature_list, $cpuser_data ) = @_;
    my $disabled_features_hr;

    # Fetch the team_user features
    if ( $ENV{'TEAM_OWNER'} ) {
        require Cpanel::Team::Features;

        if ( !$feature_list ) {
            require Cpanel::Features::Load;
            $cpuser_data  = Cpanel::Config::LoadCpUserFile::loadcpuserfile( $ENV{'TEAM_OWNER'} ) if !exists $cpuser_data->{FEATURELIST};
            $feature_list = $cpuser_data->{FEATURELIST};
        }
        my $team_owner_features        = Cpanel::Features::Load::load_featurelist($feature_list);
        my $team_user_features         = Cpanel::Team::Features::load_team_feature_list( $team_owner_features, $feature_list );
        my %updated_team_user_features = map { 'FEATURE-' . uc($_) => $team_user_features->{$_} } ( keys %$team_user_features );
        $disabled_features_hr = \%updated_team_user_features;

    }
    else {
        $disabled_features_hr = get_combined_features_for_user( $user, $feature_list, $cpuser_data );
    }

    return Cpanel::Features::Utils::cpuser_data_has_feature( $disabled_features_hr, $feature_name );
}

=head2 get_combined_features_for_user( USER, FEATURE_LIST, CPUSER_DATA_HR )

Produces a list of all features from the feature list and cpuser
data for which a user does not have privileges or has an overridden privilege.

=head3 Arguments

- user - String - The cPanel user to check. This can be Webmail user, but the check will
                  be run on the system user that owns the mail user.

- feature_list - String or undef - The name of the feature list to use when performing the
check. If undef, this value is looked up from the FEATURELIST setting in the user's
cp user file.

- CPUSER_DATA_HR - hash reference or undef - The result of an earlier loadcpuserfile call for the user.
This is purely for optimization and should not affect the function’s return.

=head3 Returns

This function returns a hash ref whose keys correspond to all of the disabled features
The value of each can be a 0 if it is disabled, and a 1 if it is overridden an enabled in their cpuser data

=cut

sub get_combined_features_for_user {
    my ( $user, $feature_list, $cpuser_data ) = @_;

    if ( !$feature_list ) {
        my $system_user = Cpanel::AcctUtils::Lookup::get_system_user_without_existence_validation($user);
        $cpuser_data ||= Cpanel::Config::LoadCpUserFile::loadcpuserfile($system_user);
        $feature_list = $cpuser_data->{'FEATURELIST'} || 'default';
    }
    elsif ( !$cpuser_data ) {
        my $system_user = Cpanel::AcctUtils::Lookup::get_system_user_without_existence_validation($user);
        $cpuser_data = Cpanel::Config::LoadCpUserFile::loadcpuserfile($system_user);
    }

    return _combine_features_from_featurelist_and_cpuser_data( $feature_list, $cpuser_data );

}

=head2 get_disabled_features_for_user_with_reasons( USER, FEATURE_LIST, CPUSER_DATA_HR )

Produces a list of all features from the feature list and cpuser
data for which a user does not have privileges.

Arguments are the same as those for C<get_disabled_features_for_user>.

This function returns a hash ref whose keys correspond to all of the disabled features and values refer to disabled reason.

=cut

sub get_disabled_features_for_user_with_reasons {
    my ( $user, $feature_list, $cpuser_data ) = @_;

    if ( !$feature_list ) {
        my $system_user = Cpanel::AcctUtils::Lookup::get_system_user_without_existence_validation($user);
        $cpuser_data ||= Cpanel::Config::LoadCpUserFile::loadcpuserfile($system_user);
        $feature_list = $cpuser_data->{'FEATURELIST'} || 'default';
    }
    elsif ( !$cpuser_data ) {
        my $system_user = Cpanel::AcctUtils::Lookup::get_system_user_without_existence_validation($user);
        $cpuser_data = Cpanel::Config::LoadCpUserFile::loadcpuserfile($system_user);
    }

    my $disabled_features = _combine_features_from_featurelist_and_cpuser_data( $feature_list, $cpuser_data );

    for my $feature ( keys %$disabled_features ) {
        if ( $disabled_features->{$feature} eq '1' ) {
            delete $disabled_features->{$feature};
        }
        elsif ( defined $cpuser_data->{$feature} ) {
            $disabled_features->{$feature} = 'cpuseroverride';
        }
        else {
            $disabled_features->{$feature} = 'featurelist';
        }
    }

    return $disabled_features;

}

=head2 _combine_features_from_featurelist_and_cpuser_data

Produces a list of all features from the feature list and cpuser
data for which a user does not have privileges.

=head3 Arguments

- feature_list - String - (Optional) The name of the feature list to use when performing the
check. If not provided, this value is looked up from the FEATURELIST setting in the user's
cp user file.

- cpuser_ref - The result of an earlier loadcpuserfile call for the user

=head3 Returns

This function returns a hash ref whose keys correspond to all of the disabled features

=cut

sub _combine_features_from_featurelist_and_cpuser_data {    ##no critic qw(RequireArgUnpacking)
    _croak('_combine_features_from_featurelist_and_cpuser_data only accepts two arguments') if scalar @_ != 2;

    my ( $feature_list, $cpuser_ref ) = @_;

    # Precaution against buggy calls since the accepted arguments were altered.
    _croak('_combine_features_from_featurelist_and_cpuser_data requires a feature_list') if !$feature_list;
    _croak('_combine_features_from_featurelist_and_cpuser_data requires a cpuser_ref')   if !ref $cpuser_ref;

    my @cpuser_feature_keys = grep { 0 == index( $_, 'FEATURE-' ) } keys %{$cpuser_ref};
    my $ref                 = {};
    Cpanel::Features::Cpanel::augment_hashref_with_features( $feature_list, $ref );

    # We do not want to overwrite keys from the cpuser data with the
    # featurelist keys since the cpanel users file entries trump
    # the featurelist
    if (@cpuser_feature_keys) {
        @{$ref}{@cpuser_feature_keys} = @{$cpuser_ref}{@cpuser_feature_keys};
    }

    return $ref;
}

sub _croak {
    require Cpanel::Carp;
    die Cpanel::Carp::safe_longmess(@_);
}

1;
