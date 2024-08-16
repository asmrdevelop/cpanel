package Cpanel::Crypt::ECDSA;

# cpanel - Cpanel/Crypt/ECDSA.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Crypt::ECDSA

=head1 SYNOPSIS

    my $ecc = Cpanel::Crypt::ECDSA->new( \$pem );

    my $pieces = $ecc->key2hash();

=head1 DESCRIPTION

This module extends L<Crypt::PK::ECC>. Interface changes are as noted
below.

=cut

#----------------------------------------------------------------------

use parent qw( Crypt::PK::ECC );

use Cpanel::Crypt::ECDSA::Data ();
use Cpanel::Exception          ();

#----------------------------------------------------------------------

=head1 METHODS

=cut

# Written this way to avoid cplint expecting POD for what is literally
# the identical interface to the inherited one. We wouldn’t normally need
# this code except Crypt::PK::ECC doesn’t honor subclassing.
*new = *_cp_new;

sub _cp_new ( $class, @args ) {
    return bless $class->SUPER::new(@args), $class;
}

=head2 $key = I<OBJ>->generate_key(..)

Wraps the base class’s method of the same name with logic that rejects
creation of a key from any curve whose name isn’t in
L<Cpanel::Crypt::ECDSA::Data>’s C<ACCEPTED_CURVES()> list.

=cut

sub generate_key ( $self, $curve_name, @args ) {

    if ( !Cpanel::Crypt::ECDSA::Data::curve_name_is_valid($curve_name) ) {
        my @accepted = Cpanel::Crypt::ECDSA::Data::ACCEPTED_CURVES();

        die Cpanel::Exception->create_raw("bad curve ($curve_name); valid are: @accepted");
    }

    return $self->SUPER::generate_key( $curve_name, @args );
}

=head2 $hr = I<OBJ>->key2hash()

Like the base class’s method of the same name, but all hash values
are in lower-case.

=cut

sub key2hash ($self) {

    my $hash = $self->SUPER::key2hash();
    tr<A-Z><a-z> for values %$hash;

    return $hash;
}

=head2 $hex = I<OBJ>->pub_hex()

Returns a hex representation of the key’s public point’s X and Y
coordinates. That string always begins with C<04>, which indicates
an uncompressed point.

It should match the C<pub> output from C<openssl ec -text>.

There could be a use to indicate a point in “compressed” form,
which would put C<02> or C<03> at the beginning of the string
and only include the X coordinate. The curve parameters in tandem
with the X coordinate determine an even/odd pair of Y coordinates;
C<02>, then, means to use the even coordinate, while C<03> means
to use the odd one. This optimizes storage size at the expense
of processing speed.

FYI, a more esoteric “hybrid” form also exists that includes both
X and Y coordinates but prefixes them with C<06> or C<07> to
indicate (redundantly) even/odd Y.

=cut

sub pub_hex ($self) {

    my $hash = $self->key2hash();

    my ( $x, $y ) = @{$hash}{qw( pub_x pub_y)};

    # Based on experimentation, it IS possible for there to be
    # leading NUL bytes in pub_x and pub_y; however, Crypt::PK::ECC
    # left-pads them for us. :)

    return ( "04$x$y" =~ tr<A-F><a-f>r );
}

1;
