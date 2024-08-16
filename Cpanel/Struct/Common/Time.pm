package Cpanel::Struct::Common::Time;

# cpanel - Cpanel/Struct/Common/Time.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Struct::Common::Time - base class for time structs

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This module is a generic interface to C structs that encode times.

=head1 SUBCLASS INTERFACE

Each subclass must define C<_PRECISION()>, a constant that indicates the
stored precision (i.e., divisions of the second).

=head1 FUNCTIONS

=head2 PACK_TEMPLATE

A C<pack()> template that produces a timeval structure as a binary
string when given seconds and microseconds (in that order).

=cut

use constant PACK_TEMPLATE => 'L!L!';

my %CLASS_PRECISION;

#----------------------------------------------------------------------

=head2 $binstr = I<CLASS>->float_to_binary( $float )

Converts $float to a binary string that the kernel recognizes as
a timeval structure.

Fractional seconds are accommodated as accurately as Perl allows.

=cut

sub float_to_binary {
    return pack(
        PACK_TEMPLATE(),

        int( $_[1] ),

        # Add 0.5 here to get rounding.
        int( 0.5 + ( $_[0]->_PRECISION() * $_[1] ) - ( $_[0]->_PRECISION() * int( $_[1] ) ) ),
    );
}

#----------------------------------------------------------------------

=head2 $float = I<CLASS>->binary_to_float( $binstr )

Converts a binary string that represents a timeval to a Perl number.

Fractional seconds are accommodated as accurately as Perl allows.

=cut

sub binary_to_float {
    return $_[0]->_binary_to_float( PACK_TEMPLATE(), $_[1] )->[0];
}

#----------------------------------------------------------------------

=head2 $floats_ar = binaries_to_floats_at( $binstr, $count, $offset )

Parses out multiple numbers at once from a given offset in the string
and returns the result in an array reference.

=cut

sub binaries_to_floats_at {
    return $_[0]->_binary_to_float(
        "\@$_[3] " . ( PACK_TEMPLATE() x $_[2] ),
        $_[1],
    );
}

#----------------------------------------------------------------------

my ( $i, $precision, @sec_psec_pairs );

sub _binary_to_float {    ## no critic qw(RequireArgUnpacking)
    @sec_psec_pairs = unpack( $_[1], $_[2] );

    $i = 0;

    my @floats;

    $precision = $CLASS_PRECISION{ $_[0] } ||= $_[0]->_PRECISION();

    while ( $i < @sec_psec_pairs ) {

        # Perl does weird things internally with floats. This appears
        # to fix problems we noticed with comparisons between floats gotten
        # from this module where the value would be passed around, and after
        # a function call would mysteriously morph from this:
        #
        #   SV = NV(0x1abbdb0) at 0x1abbdc8
        #     REFCNT = 1
        #     FLAGS = (NOK,pNOK)
        #     NV = 1547243167.343
        #
        # … to this:
        #
        #   SV = PVNV(0x1de1ee0) at 0x1a9c7a0
        #     REFCNT = 1
        #     FLAGS = (NOK,pIOK,pNOK)
        #     IV = 1547243167
        #     NV = 1547243167.343
        #     PV = 0
        #
        # Once this happens, Perl will consider the first SV to be less than
        # the second.
        #
        # Curiously, the problem goes away if we return either a string or
        # a number that was made from a string. Unfortunately, the above-described
        # breakage doesn’t appear to be reproducible directly.
        # The breakage was spotted in the initial commit of this module
        # in t/Cpanel-CachedDataStore_lock_test.t’s test_lock() method.

        push @floats, 0 + ( q<> . ( $sec_psec_pairs[$i] + ( $sec_psec_pairs[ $i + 1 ] / $precision ) ) );
        $i += 2;
    }

    return \@floats;
}

1;
