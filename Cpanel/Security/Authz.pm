package Cpanel::Security::Authz;

# cpanel - Cpanel/Security/Authz.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Security::Authz - Authorization-related security code

=head1 SYNOPSIS

All of the following throw exceptions:

    #Checks EUID only
    Cpanel::Security::Authz::verify_not_root();

    #Checks RUID, EUID, RGID, and EGID
    Cpanel::Security::Authz::verify_fully_reduced();

    Cpanel::Security::Authz::verify_user_has_feature( 'bob', 'autossl' );

    Cpanel::Security::Authz::verify_user_not_in_demo_mode('bob');

=cut

use strict;
use warnings;

use Cpanel::Exception ();

=head1 NAME

Cpanel::Security::Authz

=head1 DESCRIPTION

This module contains functions that perform authorization assertions.

=head1 SYNOPSIS

    use Cpanel::Security::Authz ();

    sub protect_me {
        my ($argument) = @_;

        Cpanel::Security::Authz::verify_fully_reduced();
        Cpanel::Security::Authz::verify_user_has_feature($Cpanel::user, 'popaccts');
        Cpanel::Security::Authz::user_not_in_demo_mode($Cpanel::user);
        ...
    }

=head1 FUNCTIONS

=over

=item verify_not_root()

Verifies that the effective UID is not root. Throws a RootProhibited exception
on failure. This assertion will pass inside a ReducedPrivileges scope.

=cut

sub verify_not_root {
    die Cpanel::Exception::create('RootProhibited') if !$>;

    return;
}

=item verify_fully_reduced()

Verified that the effective and real UIDs are not root. Throws a RootProhibited
exception on faiulre. This assertion will fail inside a ReducedPrivileges scope.

=cut

sub verify_fully_reduced {
    if ( !$> ) {
        die Cpanel::Exception::create( 'RootProhibited', 'This code forbids “[_1]” as the effective user [asis,EUID].', ['root'] );
    }

    if ( !$< ) {
        die Cpanel::Exception::create( 'RootProhibited', 'This code forbids “[_1]” as the real user [asis,RUID].', ['root'] );
    }

    if ( $) =~ m<\b0\b> ) {
        die Cpanel::Exception::create( 'RootProhibited', 'This code forbids “[_1]” in the effective group [asis,EGID].', ['root'] );
    }

    if ( $( =~ m<\b0\b> ) {
        die Cpanel::Exception::create( 'RootProhibited', 'This code forbids “[_1]” in the real group [asis,RGID].', ['root'] );
    }

    return;
}

=item verify_user_meets_requirements( $username, $requirements )

Verifies that a user meets a set of requirements.

=over 2

=item Input

=over 3

=item C<SCALAR>

The username to check requirements for.

=item C<HASHREF>

A C<HASHREF> containing the requirements that need to be met

The possible keys of the hash are:

=over 4

=item C<needs_role> - C<SCALAR> or C<HASHREF>

A role or set of roles that are required.

The hash value will be passed directly to C<Cpanel::Server::Type::Profile::Roles::verify_roles_enabled()> and
should match the input format of C<Cpanel::Server::Type::Profile::Roles::are_roles_enabled()>

=item C<needs_feature> - C<SCALAR> or C<HASHREF>

A feature or set of features that are required.

The hash value will be passed directly to C<verify_user_has_features> and should match the input format
of that function.

=item C<allow_demo> - C<SCALAR>

A boolean indicating whether or not demo mode is allowed.

If not specified it defaults to disallowing demo mode.

=back

=item Output

=over 3

Throws an exception if any of the requirements are not met, returns nothing otherwise.

=back

=back

=back

=cut

sub verify_user_meets_requirements {

    my ( $user, $ref ) = @_;

    if ( my $role = $ref->{'needs_role'} ) {
        require Cpanel::Server::Type::Profile::Roles;
        Cpanel::Server::Type::Profile::Roles::verify_roles_enabled($role);
    }

    if ( my $feature = $ref->{'needs_feature'} ) {
        verify_user_has_features( $user, $feature );
    }

    # Demo mode is denied by default, it must be explicitly enabled
    if ( !$ref->{'allow_demo'} ) {
        verify_user_not_in_demo_mode($user);
    }

    return;
}

=item verify_user_has_features( $username, $features )

Verifies that the passed in user has the required features enabled.

=over 2

=item Input

=over 3

=item C<SCALAR> or C<HASHREF>

If the input is a C<SCALAR>, it is treated as a single feature to check and this function's behavior is identical to C<verify_user_has_feature>

If the input is a C<HASHREF>, it should be in the form of:

    { match: <any|all>, features: ["feature1", "feature2", … ] }

Where:

C<match> - (optional) Determines whether C<all> the features must be enabled, or C<any> of them. If not specified, it defaults to C<all>.

C<feature> - An C<ARRAYREF> of feature names to check.

=back

=item Output

=over 3

Throws an exception if the feature requirements are not met, returns nothing otherwise.

=back

=back

=cut

sub verify_user_has_features {

    my ( $user, $feature_str_or_hr ) = @_;

    if ( ref $feature_str_or_hr ) {

        my $match = $feature_str_or_hr->{match} || 'all';

        if ( $match ne 'all' && $match ne 'any' ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be “[_2]” or “[_3]” value.', [qw(match any all)] );
        }

        my @missing_features;

        if ( defined $Cpanel::user && length $Cpanel::user && $Cpanel::user eq $user ) {    # PPI NO PARSE - falls back to Cpanel::Features::Check
            push @missing_features, grep { !Cpanel::hasfeature($_) } @{ $feature_str_or_hr->{features} };    # PPI NO PARSE - falls back to Cpanel::Features::Check
        }
        elsif ( defined $user ) {
            require Cpanel::Features::Check;
            push @missing_features, grep { !Cpanel::Features::Check::check_feature_for_user( $user, $_ ) } @{ $feature_str_or_hr->{features} };
        }

        if (@missing_features) {
            if ( $feature_str_or_hr->{match} eq 'all' ) {
                die Cpanel::Exception::create( 'FeaturesNotEnabled', [ feature_names => \@missing_features, match => 'all' ] );
            }
            if ( $feature_str_or_hr->{match} eq 'any' && scalar @missing_features == scalar @{ $feature_str_or_hr->{features} } ) {
                die Cpanel::Exception::create( 'FeaturesNotEnabled', [ feature_names => \@missing_features, match => 'any' ] );
            }
        }

    }
    else {
        return verify_user_has_feature( $user, $feature_str_or_hr );
    }

    return;
}

=item verify_user_has_feature( username, featurename )

Throws a FeatureNotEnabled exception when the provided username does not have
the provided feature enabled.

=cut

sub verify_user_has_feature {
    my ( $user, $feature ) = @_;

    if ( defined $Cpanel::user && length $Cpanel::user && $Cpanel::user eq $user ) {    # PPI NO PARSE - falls back to Cpanel::Features::Check
        if ( !Cpanel::hasfeature($feature) ) {                                          # PPI NO PARSE - falls back to Cpanel::Features::Check
            die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => $feature ] );
        }
        return;
    }

    require Cpanel::Features::Check;

    if ( defined $user && !Cpanel::Features::Check::check_feature_for_user( $user, $feature ) ) {
        die Cpanel::Exception::create( 'FeatureNotEnabled', [ feature_name => $feature ] );
    }

    return;
}

=item verify_user_not_in_demo_mode( username )

Throws a ForbiddenInDemoMode  exception when the provided username is a demo
account.

=cut

sub verify_user_not_in_demo_mode {
    my ($user) = @_;

    require Cpanel::Config::LoadCpUserFile;

    if ( Cpanel::Config::LoadCpUserFile::load($user)->{'DEMO'} ) {
        die Cpanel::Exception::create('ForbiddenInDemoMode');
    }

    return;
}

=item verify_user_has_access_to_account

A thin wrapper around Cpanel::AccessControl::user_has_access_to_account

=over 2

=item Input

=over 3

=item C<SCALAR>

    The account to access.

=back

=item Output

Returns 1 or dies with the AccessDeniedToAccount exception.

=back

=back

=cut

sub verify_user_has_access_to_account {
    my ( $user, $account ) = @_;

    require Cpanel::AccessControl;
    if ( !Cpanel::AccessControl::user_has_access_to_account( $user, $account ) ) {

        die Cpanel::Exception::create( 'AccessDeniedToAccount', [ user => $user, account => $account ] );
    }

    return 1;
}

1;
