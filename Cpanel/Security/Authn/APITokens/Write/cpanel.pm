package Cpanel::Security::Authn::APITokens::Write::cpanel;

# cpanel - Cpanel/Security/Authn/APITokens/Write/cpanel.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::APITokens::Write::cpanel

=head1 SYNOPSIS

    my $wrobj = Cpanel::Security::Authn::APITokens::Write::cpanel->new( { user => 'steve' } );

    $wrobj->create_token( {
        name => 'god',
        has_full_access => 1,
    } );

    $wrobj->update_token( {
        name => 'god',
        new_name => 'mortal',
        has_full_access => 0,
        features => ['ssh'],
    } );

=head1 DESCRIPTION

This is an end class for write access to the cPanel API tokens datastore.
It extends L<Cpanel::Security::Authn::APITokens::Write> as well as
L<Cpanel::Security::Authn::APITokens::cpanel>.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Security::Authn::APITokens::Write
  Cpanel::Security::Authn::APITokens::cpanel
);

use Cpanel::Security::Authn::APITokens::Validate::cpanel ();

use Cpanel::PwCache ();

use constant {
    _BASE_DIR_PERMISSIONS   => 0711,
    _TOKEN_FILE_PERMISSIONS => 0640,
};

sub _validate_for_create {
    my ( $self, $opts_hr ) = @_;

    Cpanel::Security::Authn::APITokens::Validate::cpanel->validate_creation( $self->{'_username'}, $opts_hr );

    return;
}

sub _validate_for_update {
    my ( $self, $token_hr, $opts_hr ) = @_;

    Cpanel::Security::Authn::APITokens::Validate::cpanel->validate_update( $self->{'_username'}, $token_hr, $opts_hr );

    return;
}

# called from tests
sub _normalize_token_data {
    my ( $self, $opts_hr ) = @_;

    if ( $opts_hr->{'has_full_access'} ) {
        $opts_hr->{'has_full_access'} = 1;
        @{ $opts_hr->{'features'} } = ();
    }
    else {
        $opts_hr->{'has_full_access'} = 0;

        require Cpanel::ArrayFunc::Uniq;
        $opts_hr->{'features'} //= [];
        @{ $opts_hr->{'features'} } = sort( Cpanel::ArrayFunc::Uniq::uniq( @{ $opts_hr->{'features'} } ) );
    }

    return;
}

sub _TOKEN_FILE_OWNERSHIP {
    my ( $self, $username ) = @_;

    my $gid = ( Cpanel::PwCache::getpwnam_noshadow($username) )[3] or do {
        die "No GID found for user “$username”!";
    };

    return ( 0, $gid );
}

1;
