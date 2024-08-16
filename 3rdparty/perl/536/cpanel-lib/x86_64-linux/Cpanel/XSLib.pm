package Cpanel::XSLib;

# cpanel - Cpanel/XSLib.pm                         Copyright 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION;

use XSLoader ();

BEGIN {
    $VERSION = '0.07';
    XSLoader::load();
}

=encoding utf-8

=head1 NAME

Cpanel::XSLib

=head1 DESCRIPTION

This module contains C implementations of pieces of logic that are
useful for managing F<httpd.conf> and potentially elsewhere.

=head1 FUNCTIONS

=head2 increase_hash_values_past_threshold( \%hash, $threshold, $increase )

For each value of %hash, augments the value by $increase if the value
already meets or exceeds $threshold.

(Note that $increase may be negative!)

Pure-perl equivalent:

    $_ += $increase for ( grep { $_ >= $threshold } values %hash );

=head2 $index = filter_one( \@array, $string )

Removes up to 1 occurrence of $string in @array. Returns the index
of the now-removed element, or -1 if no such element exists.

Pure-perl equivalent:

    my $index = 0;

    $index++ while $index < @array && $array[$index] ne $needle;

    return -1 if $index == @array;

    splice( @array, $index, 1 );

    return $index;

=head2 $index = get_array_index_eq( \@array, $string )

Like C<filter_one()> but just returns the index of the first @array
member that string-equals $string.

Pure-perl equivalent:

    my $index = 0;

    $index++ while $index < @array && $array[$index] ne $needle;

    return ($index < @array) ? $index : -1;

=head2 $index = get_array_index_start_chr( \@array, $bytenum )

Like C<get_array_index_eq()> but just compares the first byte of each
@array member against $bytenum. So to check for C<*> at the start of
any @array member, do:

    get_array_index_start_chr( \@array, ord '*' );

Pure-perl equivalent:

    my $index = 0;

    $index++ while $index < @array && 0 != rindex( $array[$index], '*', 0 );

    return ($index < @array) ? $index : -1;

=cut

1;
