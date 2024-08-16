package Cpanel::Security::Authn::APITokens::Object::whostmgr;

# cpanel - Cpanel/Security/Authn/APITokens/Object/whostmgr.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::Object::whostmgr

=head1 SYNOPSIS

    bless $token_hr, 'Cpanel::Security::Authn::APITokens::Object::whostmgr';

    if ( $token_hr->has_acl('someacl') ) { .. }

    if ( $token_hr->has_root() ) { .. }


=head1 DESCRIPTION

This is class implements interactions with WHM API token objects.
It subclasses L<Cpanel::Security::Authn::APITokens::Object>.

=head1 INTERNAL STRUCTURE

This class postdates WHM API tokens; prior to this class, WHM API tokens
were represented as plain hashes, and every consumer of that data
structure implemented its own logic to inspect the hash.

The present class is meant to preserve compatibility with existing code;
hence, the object’s internal structure must remain consistent with the
previous hash reference structure.

New code will probably be advantaged to use the accessor methods that
this class provides rather than continuing to reach directly into the
object internals.

=head1 TODO

We should determine whether all callers can be migrated to use
object methods.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Security::Authn::APITokens::Object';

#----------------------------------------------------------------------

=head1 INSTANTIATION

C<new()> for this class expects the following (in addition to
the base class’s expected parameters):

=over

=item * C<acls> - optional, or array reference

=back

=head1 EXPORT FORMAT

C<export()> for this class exports a hash reference with the following
members:

=over

=item * C<name> - The token name

=item * C<create_time> - in epoch seconds

=item * C<expires_at> - in epoch seconds

=item * C<acls> - Optional; if not present, indicates that the token has
access to the same ACLs as the user.

=back

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $yn = I<OBJ>->has_acl( $ACL_NAME )

Returns a boolean that indicates whether the token indicates support
(whether explicitly or via full-access state) for the given ACL.

=cut

sub has_acl {
    my ( $self, $aclname ) = @_;

    return !!( $self->has_full_access() || grep { $_ eq $aclname } @{ $self->{'acls'} } );
}

#----------------------------------------------------------------------

=head2 I<OBJ>->filter_acls( \%ACLS )

A special-use form of C<has_acl()> that B<alters> %ACLS as per the token’s
ACL limitations. Keys of %ACLS are ACL names (e.g., C<create-acct>), and
values are booleans to indicate availability.

Specific rules:

=over

=item * A full-access token leaves the passed-in %ACLS alone.

=item * Otherwise, if the passed-in %ACLS has the C<all> ACL
(i.e., C<all> is truthy), then %ACLS will reflect exactly
the token’s ACLs list.

=item * Otherwise, any %ACLS member that is not one of the
token’s ACLs is set to falsy.

=back

=cut

sub filter_acls {
    my ( $self, $user_acls_hr ) = @_;

    # If the token is full-access, then just give the user’s ACLs.
    if ( !$self->has_full_access() ) {

        # The token isn’t full-access, but the reseller has root.
        # So return the token’s privileges.
        if ( $user_acls_hr->{'all'} ) {
            %$user_acls_hr = (
                ( map { ( $_ => q<> ) } keys %$user_acls_hr ),
                ( map { ( $_ => 1 ) } @{ $self->{'acls'} } ),
            );
        }
        else {

            # The reseller doesn’t have root, and neither does the token have
            # full access. This means we filter the reseller’s ACLs by the token.
            # We deny all ACLs that are not BOTH in the token AND truthy
            # in $user_acls_hr.

            my %token_acls;
            @token_acls{ @{ $self->{'acls'} } } = ();

            $user_acls_hr->{$_} &&= exists $token_acls{$_} for keys %$user_acls_hr;
        }
    }

    return;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->has_full_access()

Returns a boolean that indicates whether the token indicates full access,
i.e., the same access rights as the reseller who owns the token.

=cut

sub has_full_access {
    my ($self) = @_;

    return !exists $self->{'acls'} || !!grep { $_ eq 'all' } @{ $self->{'acls'} };
}

#----------------------------------------------------------------------

sub _export {

    # Ideally, the export should explicitly indicate that the token
    # has full access (i.e., to the reseller’s ACLs).
    #
    # … but that’s more change than is needed in an already-overgrown
    # branch. It doesn’t appear to break anything since filter_acls()
    # prevents root escalation, FYI.
    #
    # local $_[0]->{'acls'} = ['all'] if !exists $_[0]->{'acls'};

    return $_[0]->SUPER::_export();
}

1;
