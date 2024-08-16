package Cpanel::Crypt::ECDSA::Utils;

# cpanel - Cpanel/Crypt/ECDSA/Utils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Crypt::ECDSA::Utils - assorted ECDSA goodies

=head1 SYNOPSIS

    my $chex = Cpanel::Crypt::ECDSA::Utils::compress_public_point($pub_hex);

=head1 DESCRIPTION

This module contains logic for manipulating various aspects of
ECDSA keys.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $hex = compress_public_point( $PUBLIC_HEX )

Takes the hex encoding of a public point (B<uncompressed>) and
returns its “compressed” form.

=cut

sub compress_public_point ($publicxy) {
    die "Need uncompressed, not $publicxy" if 0 != rindex( $publicxy, '04', 0 );

    my $y = substr( $publicxy, 1 + length($publicxy) / 2, length($publicxy), q<> );

    substr( $publicxy, 1, 1, substr( $y, -1 ) =~ tr<13579bdf><> ? 3 : 2 );

    return $publicxy;
}

=head2 $hex = decompress_public_point( $CURVE_NAME, $COMPRESSED_HEX )

The inverse operation from C<compress_public_point()>: takes a curve name
and the compressed public point, and returns the uncompressed point.

=cut

my %Y_BIT;

BEGIN {
    %Y_BIT = (
        '02' => 0,
        '03' => 1,
    );
}

sub decompress_public_point ( $curve_name, $comp_hex ) {

    local ( $@, $! );
    require Crypt::OpenSSL::EC;
    require Crypt::OpenSSL::Bignum;
    require Cpanel::Crypt::ECDSA::Data;

    my $nid = Cpanel::Crypt::ECDSA::Data::get_openssl_nid($curve_name);

    my $y_bit = $Y_BIT{ substr $comp_hex, 0, 2 } // do {
        die "Invalid compressed point: $comp_hex";
    };

    substr( $comp_hex, 0, 2, q<> );

    my $compressed = Crypt::OpenSSL::Bignum->new_from_hex($comp_hex);

    my $ctx   = Crypt::OpenSSL::Bignum::CTX->new();
    my $group = Crypt::OpenSSL::EC::EC_GROUP::new_by_curve_name($nid);
    my $point = Crypt::OpenSSL::EC::EC_POINT::new($group);

    # Everything above this point is just setup; the below is the
    # actual decompression:

    Crypt::OpenSSL::EC::EC_POINT::set_compressed_coordinates_GFp(
        $group, $point, $compressed, $y_bit, $ctx,
    );

    my $hex = Crypt::OpenSSL::EC::EC_POINT::point2hex(
        $group, $point,
        Crypt::OpenSSL::EC::POINT_CONVERSION_UNCOMPRESSED(),
        $ctx,
    );

    $hex =~ tr<A-F><a-f>;

    return $hex;
}

1;
