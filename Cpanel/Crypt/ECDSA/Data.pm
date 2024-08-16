package Cpanel::Crypt::ECDSA::Data;

# cpanel - Cpanel/Crypt/ECDSA/Data.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Crypt::ECDSA::Data

=head1 DESCRIPTION

This module contains various constants and routines that are useful
for dealing with ECDSA.

=cut

#----------------------------------------------------------------------

use Cpanel::Context ();

use constant {

    # crypto/objects/obj_mac.num
    _OPENSSL_NID_prime256v1 => 415,
    _OPENSSL_NID_secp384r1  => 715,

    _OID_prime256v1 => '1.2.840.10045.3.1.7',
    _OID_secp384r1  => '1.3.132.0.34',
};

use constant _ALIASES_prime256v1 => qw( P-256  secp256r1 );
use constant _ALIASES_secp384r1  => qw( P-384  ansip384r1 );

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 ACCEPTED_CURVES

A list of canonical names of accepted curves, in the order
of preference that we present in the API.

=cut

use constant ACCEPTED_CURVES => (
    'secp384r1',
    'prime256v1',

    # Sectigo signs certificates using this curve,
    # but Chrome doesn’t support it.
    # 'secp521r1',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = curve_name_is_valid($NAME)

Returns a boolean that indicates whether the given $NAME is a valid
ECDSA curve name (as per this module).

This is convenience logic that just compares $NAME against
C<ACCEPTED_CURVES>.

=cut

sub curve_name_is_valid ($name) {
    return 0 + grep { $_ eq $name } ACCEPTED_CURVES;
}

=head2 $str = get_oid($NAME)

Gets the OID for a curve with the given (canonical) $NAME.

=cut

sub get_oid ($name) {
    return __PACKAGE__->can("_OID_$name")->();
}

=head2 $nid = get_openssl_nid($NAME)

Like C<get_oid()> but returns the curve’s OpenSSL NID.

=cut

sub get_openssl_nid ($name) {
    my $nid = __PACKAGE__->can("_OPENSSL_NID_$name") or do {
        _die_bad_curve_name($name);
    };

    return $nid->();
}

=head2 @aliases = get_aliases($NAME)

Gets a list of aliases for the given curve $NAME.

=cut

sub get_aliases ($name) {

    Cpanel::Context::must_be_list();

    return __PACKAGE__->can("_ALIASES_$name")->();
}

=head2 $name = get_canonical_name_or_die($NAME)

Returns a curve’s “canonical” name.

=cut

sub get_canonical_name_or_die ($name) {
    for my $cname ( ACCEPTED_CURVES() ) {
        my $this_yn = ( $cname eq $name );

        $this_yn ||= grep { $_ eq $name } get_aliases($cname);

        return $cname if $this_yn;
    }

    die "No canonical name found for “$name”!";
}

# Gotten by comparing results of these algorithms:
#   RSA: https://crypto.stackexchange.com/questions/8687/security-strength-of-rsa-in-relation-with-the-modulus-size (the one written in bc)
#   ECC: http://crypto.stackexchange.com/questions/31439/how-do-i-get-the-equivalent-strength-of-an-ecc-key
#
# NB: OpenSSL’s “security bits” would have been a better metric than RSA
# equivalence for comparing ECDSA and RSA key strengths, but security bits
# require OpenSSL 1.1.0+, which not all supported OSes use.
#
my %EQ_RSA_LEN = (
    prime256v1 => 2529,
    secp384r1  => 6692,
);

sub get_equivalent_rsa_modulus_length ($curve_name) {

    return $EQ_RSA_LEN{$curve_name} || _die_bad_curve_name($curve_name);
}

sub _die_bad_curve_name ($curve_name) {
    require Carp;
    Carp::croak("bad curve name: $curve_name");

    return;
}

1;
