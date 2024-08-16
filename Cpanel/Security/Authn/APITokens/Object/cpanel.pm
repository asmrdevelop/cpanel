package Cpanel::Security::Authn::APITokens::Object::cpanel;

# cpanel - Cpanel/Security/Authn/APITokens/Object/cpanel.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::Object::cpanel

=head1 SYNOPSIS

    my $token = Cpanel::Security::Authn::APITokens::Object::cpanel->new(
        has_full_access => 0,
        features => [ 'feature1', 'feature2' ],
        name => 'mytoken',
        create_time => 1234566,
        expires_at  => 1234566,
    );

=head1 DESCRIPTION

This is class implements interactions with cPanel API token objects.
It subclasses L<Cpanel::Security::Authn::APITokens::Object>.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Security::Authn::APITokens::Object';

#----------------------------------------------------------------------

=head1 INSTANTIATION

C<new()> for this class expects the following (in addition to
the base class’s expected parameters):

=over

=item * C<has_full_access> - boolean

=item * C<features> - array reference

=back

=head1 EXPORT FORMAT

C<export()> for this class exports a hash reference with the following
members:

=over

=item * C<name> - The token name

=item * C<create_time> - in epoch seconds

=item * C<expires_at> - in epoch seconds

=item * C<has_full_access> - boolean

=item * C<features> - Empty if C<has_full_access> is truthy; otherwise
gives the token’s specific features.

=back

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $yn = I<OBJ>->has_feature( $FEATURE_NAME )

Returns a boolean that indicates whether the token indicates support
(whether explicitly or via full-access state) for the given feature.

=cut

sub has_feature {
    my ( $self, $feature ) = @_;

    return !!( $self->{'has_full_access'} || grep { $_ eq $feature } @{ $self->{'features'} } );
}

#----------------------------------------------------------------------

=head2 $yn = I<OBJ>->has_full_access()

Returns a boolean that indicates whether the token can access
all of the cPanel user’s features.

=cut

sub has_full_access {
    my ($self) = @_;

    return !!$self->{'has_full_access'};
}

1;
