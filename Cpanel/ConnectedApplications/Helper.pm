package Cpanel::ConnectedApplications::Helper;

# cpanel - Cpanel/ConnectedApplications/Helper.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 NAME

Cpanel::ConnectedApplications::Helper

=head1 SYNOPSIS
    require Cpanel::ConnectedApplications::Helper;

    my $jwt_decoded = eval {
      Cpanel::ConnectedApplications::Helper->new()->validate_jwt( $encoded_jwt )
    };
    if ( my $exception = $@ ) { warn $exception };

=head1 DESCRIPTION

This module provides methods to handle functionality for ConnectedApplications.

=cut

=head1 FUNCTIONS

=head2 new

Create a new Helper object

=cut

sub new {
    return bless {}, shift;
}

=head2 _is_whitelisted

Determines if the issuing domain listed in the JWT is an authorized source for JSON Web Keys.

Returns 1 if the domain is an authorized source otherwise returns 0.

=cut

sub _is_whitelisted {
    my ( $self, $url ) = @_;
    require Cpanel::Logger;

    # TODO: make this configurable via Tweak setting
    my @domains = (
        'https://platform360.io/.well-known/jwks.json',
        'https://my.plesk.com/.well-known/jwks.json',
    );

    # for 360 development
    my @dev_domains = (
        'http://127.0.0.1:8080/.well-known/jwks.json',
        'http://localhost:8080/.well-known/jwks.json',
        'https://127.0.0.1:8080/.well-known/jwks.json',
        'https://localhost:8080/.well-known/jwks.json',
    );

    push( @domains, @dev_domains )
      if Cpanel::Logger::is_sandbox();

    return ( grep { $_ eq $url } @domains ) ? 1 : 0;
}

=head2 _pub_key_pem_from_jwk

Takes a public JSON Web Key and returns it in X.509 PEM format.

=cut

sub _pub_key_pem_from_jwk {
    my ( $self, $jwk ) = @_;
    require Crypt::PK::RSA;

    my $pk = Crypt::PK::RSA->new();
    return $pk->import_key(
        {
            kty => $jwk->{kty}, n => $jwk->{n}
            , e => $jwk->{e}
        }
    )->export_key_pem('public_x509');
}

=head2 validate_jwt

Decodes a JSON Web Token and verifies the signature.

Returns a decoded JWT if the signature is valid otherwise dies.

=cut

sub validate_jwt {
    my ( $self, $jwt_encoded ) = @_;

    # NOTE: We decode the token twice because the URL needed to get the
    # public key to validate the token is contained within the token
    require JSON::WebToken;

    my $jwt_decoded = eval { JSON::WebToken::decode_jwt( $jwt_encoded, "", 0, [] ) };
    if ( my $exception = $@ ) {
        die 'jwt: ' . $exception->code;
    }

    my $issuer = $jwt_decoded->{iss};
    if ( $self->_is_whitelisted($issuer) ) {

        require Cpanel::HTTP::Client;
        my $resp_obj = Cpanel::HTTP::Client->new()->get($issuer);

        if ( $resp_obj->success() ) {

            require JSON::XS;

            my $jwks = JSON::XS::decode_json( $resp_obj->content() );
            my $pem  = $self->_pub_key_pem_from_jwk( $jwks->{keys}[0] );

            # decode the jwt again but with the pem to validate
            $jwt_decoded = eval { JSON::WebToken::decode_jwt( $jwt_encoded, $pem, 1, ["RS512"] ) };
            if ( my $exception = $@ ) {
                die 'jwt: ' . $exception->code;
            }
        }
        else {
            die sprintf( "http: %d: %s", $resp_obj->status(), $resp_obj->reason() );
        }

    }
    else {
        die 'invalid_domain';
    }

    return $jwt_decoded;

}

1;
