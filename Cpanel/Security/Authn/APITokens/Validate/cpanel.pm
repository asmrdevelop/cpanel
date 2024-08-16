package Cpanel::Security::Authn::APITokens::Validate::cpanel;

# cpanel - Cpanel/Security/Authn/APITokens/Validate/cpanel.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::Validate::cpanel

=head1 SYNOPSIS

    my @parts = Cpanel::Security::Authn::APITokens::Validate::cpanel->NON_NAME_TOKEN_PARTS();

    Cpanel::Security::Authn::APITokens::Validate::cpanel->validate_creation(
        $username,
        \%params,
    );

    Cpanel::Security::Authn::APITokens::Validate::cpanel->validate_update(
        $username,
        \%token_data_hr,
        \%params,
    );

=head1 DESCRIPTION

This module provides validation of the parts of a cPanel API token
that pertain specifically to the C<cpanel> service: C<has_full_access>
and C<features>.

=head1 CPANEL-SPECIFIC NOTES

Tokens for cPanel can either have a list of C<features> or can be set
C<has_full_access>. These are mutually exclusive, and at least one must
be given.

On update, if you wish to reduce a full-access token’s privileges,
you must explicitly revoke the C<has_full_access> flag.

You may not confer C<features> that the user itself can’t
already access.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Security::Authn::APITokens::Validate';

use Cpanel::Exception ();

use constant _NON_NAME_TOKEN_PARTS => (
    'features',
    'has_full_access',
);

#----------------------------------------------------------------------

=head1 CLASS METHODS

=head2 I<CLASS>->validate_creation( $USERNAME, \%PARAMS )

Same as L<Cpanel::Security::Authn::APITokens::Validate>’s
method of the same name but requires a username and implements
validation of C<has_full_access> and C<features>.

=cut

our $_USERNAME;

sub validate_creation {
    my ( $class, $username, $opts_hr ) = @_;

    local $_USERNAME = $username;

    $class->SUPER::validate_creation($opts_hr);

    my $features = $opts_hr->{'features'} || [];

    if ( !$opts_hr->{'has_full_access'} && !@$features ) {
        die Cpanel::Exception->create('Specify either a list of features or full access.');
    }

    return;
}

#----------------------------------------------------------------------

=head2 I<CLASS>->validate_update( $USERNAME, \%TOKEN_DATA, \%PARAMS )

Similar to C<create()> above.

=cut

sub validate_update {
    my ( $class, $username, $token_hr, $opts_hr ) = @_;

    local $_USERNAME = $username;

    $class->SUPER::validate_update($opts_hr);

    my @features = @{ $opts_hr->{'features'} // $token_hr->{'features'} // [] };

    my $disabled_full_access = !$opts_hr->{'has_full_access'};
    $disabled_full_access &&= defined $opts_hr->{'has_full_access'};

    if ( $token_hr->{'has_full_access'} ) {
        if ( @features && !$disabled_full_access ) {
            die Cpanel::Exception->create('You must revoke full access to assign individual features.');
        }
    }
    elsif ( !@features ) {
        if ($disabled_full_access) {
            die _err_no_features();
        }
    }

    my %new = map { $_ => $opts_hr->{$_} // $token_hr->{$_} } _NON_NAME_TOKEN_PARTS();

    my $features = $new{'features'} || [];

    if ( !$new{'has_full_access'} && !@$features ) {
        die _err_no_features();
    }

    return;
}

#----------------------------------------------------------------------

sub _err_no_update {
    return Cpanel::Exception->create('Specify a new name or updated features.');
}

sub _err_no_features {
    return Cpanel::Exception->create('Specify either a list of features or full access.');
}

sub _validate_service_parts {
    my ( $class, $opts_hr ) = @_;

    my $username = $_USERNAME;

    my @features = @{ $opts_hr->{'features'} // [] };

    if ( $opts_hr->{'has_full_access'} ) {
        if (@features) {
            die Cpanel::Exception->create("An [asis,API] token with full access does not need individual features.");
        }
    }
    elsif (@features) {
        if ( my @lack = _get_unsupported_features( $username, @features ) ) {
            @lack = sort @lack;

            die Cpanel::Exception->create( 'The following [numerate,_1,does,do] not refer to [numerate,_1,a feature,features] that you can access: [join,~, ,_2]', [ 0 + @lack, \@lack ] );
        }
    }

    return;
}

# overridden in external tests
sub _get_unsupported_features {
    my ( $username, @features ) = @_;

    require Cpanel::Features;
    require Cpanel::Features::Check;
    require Cpanel::Set;
    require Cpanel::Config::LoadCpUserFile;

    my $cpuser_data = Cpanel::Config::LoadCpUserFile::load($username);

    my @disabled = grep { !Cpanel::Features::Check::check_feature_for_user( $username, $_, $cpuser_data->{'FEATURELIST'}, $cpuser_data ) } @features;

    my @unrecognized = Cpanel::Set::difference(
        \@features,
        [ Cpanel::Features::load_feature_names() ],
    );

    return ( @disabled, @unrecognized );
}

1;
