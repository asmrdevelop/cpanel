package Cpanel::Market::Provider::cPStore::Decrypt;

# cpanel - Cpanel/Crypt/Decrypt.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Crypt::Decrypt - Public-key decryption

=head1 SYNOPSIS

    my $decrypted_string = Cpanel::Market::Provider::cPStore::Decrypt::action_url(
        $key_parse, $key_pem,
        $encrypted_url,
    );

=head1 DESCRIPTION

This module provides reusable convenience logic for algorithm-agnostic
decryption via public keys.

=cut

#----------------------------------------------------------------------

use MIME::Base64 ();

use Cpanel::Crypt::Algorithm ();
use Cpanel::Crypt::Constants ();    ## PPI NO PARSE - mis-parse

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $str = action_url( $KEY_PARSE_HR, $KEY_PEM, $ENCRYPTED_URL )

Decrypts $ENCRYPTED_URL and returns the result.

$KEY_PARSE_HR must be compatible with
C<Cpanel::Crypt::Algorithm::dispatch_from_parse()>.
$KEY_PEM is the key in PEM format.

=cut

sub action_url ( $key_parse, $key_pem, $string ) {
    if ( length $string ) {
        my $ciphertext = MIME::Base64::decode($string);

        local ( $@, $! );

        $string = Cpanel::Crypt::Algorithm::dispatch_from_parse(
            $key_parse,
            rsa => sub {
                require Crypt::PK::RSA;
                my $key_obj = Crypt::PK::RSA->new( \$key_pem );

                return $key_obj->decrypt( $ciphertext, 'v1.5' );
            },
            ecdsa => sub {
                require Crypt::PK::ECC;
                my $key_obj = Crypt::PK::ECC->new( \$key_pem );

                require Convert::BER::XS;

                my $decrypted = q<>;

                # ECC doesn’t provide out-of-the-box encryption the way RSA does.
                # As a result, various crypto libraries implement this pattern
                # differently. cPStore uses libtomcrypt’s approach of encrypting
                # a message in chunks; the result is an ordered set of ASN.1
                # documents, concatenated end-to-end. To decrypt this we have to
                # divvy up the concatenated string into separate ASN.1 documents,
                # give each of those to decrypt(), then concatenate the result.

                while ( length $ciphertext ) {

                    # We use Convert::BER::XS solely to tell us how long each
                    # individual ASN.1 document is. decrypt() is what will
                    # actually care about the contents of the documents.

                    my ( undef, $len ) = Convert::BER::XS::ber_decode_prefix($ciphertext);

                    $decrypted .= $key_obj->decrypt(
                        substr( $ciphertext, 0, $len, q<> ),
                    );
                }

                return $decrypted;
            },
        );
    }

    return $string;
}

1;
