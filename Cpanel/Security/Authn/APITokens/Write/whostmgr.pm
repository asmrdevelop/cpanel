package Cpanel::Security::Authn::APITokens::Write::whostmgr;

# cpanel - Cpanel/Security/Authn/APITokens/Write/whostmgr.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 WHM-SPECIFIC NOTES

=over

=item * C<create_token> - optionally accepts C<acls>, which is
a list of ACLs to assign to a token.
If no ACLs are specified then the token will implicitly inherit all ACLs
assigned to the WHM user.

The same list is returned, if given.

=item * C<import_token> - Same as for C<create_token>.

=item * C<update_token> - optionally accepts C<acls>, which
replaces the token’s list of assigned ACLs. If no ACLs are given then
the previously configured list of ACLs is retained.

=back

The same list is returned, if given.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Security::Authn::APITokens::Write
  Cpanel::Security::Authn::APITokens::whostmgr
);

use Cpanel::Security::Authn::APITokens::Validate::whostmgr ();

use constant _BASE_DIR_PERMISSIONS => 0700;

use constant _TOKEN_FILE_PERMISSIONS => 0600;

use constant _TOKEN_FILE_OWNERSHIP => ( 0, 0 );

#----------------------------------------------------------------------

sub _validate_for_create {
    my ( $self, $opts_hr ) = @_;

    Cpanel::Security::Authn::APITokens::Validate::whostmgr->validate_creation($opts_hr);

    return;
}

sub _validate_for_update {
    my ( $self, $token_hr, $opts_hr ) = @_;

    Cpanel::Security::Authn::APITokens::Validate::whostmgr->validate_update($opts_hr);

    return;
}

# called from tests
sub _normalize_token_data {
    my ( $self, $opts_hr ) = @_;

    require Cpanel::ArrayFunc::Uniq;

    # The original WHM API tokens implementation didn’t include access
    # control, as a result of which an absence of “acls” is interpreted
    # as full access.

    if ( $opts_hr->{'acls'} ) {
        @{ $opts_hr->{'acls'} } = sort( Cpanel::ArrayFunc::Uniq::uniq( @{ $opts_hr->{'acls'} } ) );
    }
    else {

        # The logic that checks for the default-to-full-access state
        # looks specifically for *nonexistent* “acls”.
        delete $opts_hr->{'acls'};
    }

    if ( $opts_hr->{'whitelist_ips'} ) {
        @{ $opts_hr->{'whitelist_ips'} } = $self->_normalize_ip_list( @{ $opts_hr->{'whitelist_ips'} } );
    }
    else {

        # The logic that checks for the default-to-any-ip state
        # looks specifically for *nonexistent* whitelist_ips.
        delete $opts_hr->{'whitelist_ips'};
    }

    if ( defined $opts_hr->{'expires_at'} && $opts_hr->{'expires_at'} eq 0 ) {
        $opts_hr->{'expires_at'} = undef;
    }

    return;
}

1;
