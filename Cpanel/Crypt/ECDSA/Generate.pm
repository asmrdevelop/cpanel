package Cpanel::Crypt::ECDSA::Generate;

# cpanel - Cpanel/Crypt/ECDSA/Generate.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Crypt::ECDSA::Generate - ECDSA key generation

=head1 SYNOPSIS

    my $key_pem = Cpanel::Crypt::ECDSA::Generate::pem('prime256v1');

=head1 DESCRIPTION

This module contains key generation logic for ECDSA.

=head1 SEE ALSO

L<Crypt::PK::ECC> and L<Crypt::Perl> can also generate ECDSA keys.

=cut

#----------------------------------------------------------------------

use Crypt::OpenSSL::Bignum ();
use Crypt::OpenSSL::EC     ();
use Crypt::Format          ();

use Cpanel::Crypt::ECDSA::Data ();

my %obj_cache;

END { %obj_cache = () }

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $pem = pem( $CURVE_NAME )

Generate a new ECDSA private key, and return its PEM representation.

The key will contain the curve name stored by name and the public point
in I<uncompressed> form.

=cut

sub pem ($curve_name) {
    my $nid = Cpanel::Crypt::ECDSA::Data::get_openssl_nid($curve_name);

    # We might as well cache these:
    my $ecgroup = $obj_cache{"group_$nid"} ||= do {
        Crypt::OpenSSL::EC::EC_GROUP::new_by_curve_name($nid);
    };

    my $eckey = Crypt::OpenSSL::EC::EC_KEY::new_by_curve_name($nid);

    $eckey->generate_key();

    my $public = $eckey->get0_public_key();

    my $bigctx = Crypt::OpenSSL::Bignum::CTX->new();

    my $x = Crypt::OpenSSL::Bignum->new();
    my $y = Crypt::OpenSSL::Bignum->new();

    Crypt::OpenSSL::EC::EC_POINT::get_affine_coordinates_GFp(
        $ecgroup,
        $public,
        $x, $y,
        $bigctx,
    );

    return _to_pem( $curve_name, $eckey->get0_private_key(), $x, $y );
}

#----------------------------------------------------------------------
# The below is a custom ASN.1 serializer for ECDSA keys. It’s dramatically
# faster than using Crypt::PK::ECC import_key(). For a more “proper”
# implementation in pure Perl, see Crypt::Perl::ECDSA::PrivateKey.

my %_BIN_LENGTH = (
    prime256v1 => 32,
    secp384r1  => 48,
);

my %_STATIC_DER_PIECES = (
    prime256v1 => [
        "\x30\x77\x02\x01\x01\x04\x20",
        "\xa0\x0a\x06\x08\x2a\x86\x48\xce\x3d\x03\x01\x07\xa1\x44\x03\x42\x00",
    ],

    secp384r1 => [
        "\x30\x81\xa4\x02\x01\x01\x04\x30",
        "\xa0\x07\x06\x05\x2b\x81\x04\x00\x22\xa1\x64\x03\x62\x00",
    ],
);

sub _to_pem ( $curve_name, $private, $x, $y ) {
    my $binlen = $_BIN_LENGTH{$curve_name};

    $private = _lpad_nul( $private, $binlen );

    my $public_bin = "\x04" . _lpad_nul( $x, $binlen ) . _lpad_nul( $y, $binlen );

    my $der = $_STATIC_DER_PIECES{$curve_name};

    $der = $der->[0] . $private . $der->[1] . $public_bin;

    return Crypt::Format::der2pem( $der, 'EC PRIVATE KEY' );
}

sub _lpad_nul ( $bignum, $length ) {
    my $string = $bignum->to_bin();
    substr( $string, 0, 0, "\0" x ( $length - length($string) ) );

    return $string;
}

1;
