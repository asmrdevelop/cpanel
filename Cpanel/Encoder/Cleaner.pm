package Cpanel::Encoder::Cleaner;

# cpanel - Cpanel/Encoder/Cleaner.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Encoder::Cleaner;

=head1 SYNOPSIS

    my $malEncoded = ...;
    my $cleanString = Cpanel::Encoder::Cleaner::get_clean_utf_string($malEncoded);

=head1 DESCRIPTION

Cpanel::Encoder::Cleaner is a set of routines for re-encoding malformed UTF8
strings that generally come from interfaces where the encoding was not known
and the Perl libraries or Perl modules have already made an attempt to encode
the obviously non-UTF8 bytes into a UTF8 string.

These routines permit one to reencode the UTF8 string, replacing the bytes
that do not map to a valid UTF8 character with the UTF8 replacement byte
'\x{ef}\x{bf}\x{bd}'.

Due to the cost of rewriting strings, this utility is mean to only be used
where malformed encodings are known to enter the system, and is not meant
to be used as a general facility for all strings.

=cut

use strict;
use warnings;

use Carp;

=head1 METHODS

=head2 Cpanel::Encoder::Cleaner::push_replacement()

Pushes the UTF8 replacmeent character to the end of a byte array.

Adds the byte sequence for the UTF8 replacement character, 0xef 0xbf 0xbd,
to the end of the byte array.

=head3 Required arguments

=over 4

=item byte_array

A byte array reference receving the character.

=back

=cut

sub push_replacement {
    my ($byte_array_ref) = @_;
    push( @$byte_array_ref, 0xef, 0xbf, 0xbd );
    return;
}

=head2 Cpanel::Encoder::Cleaner::replace_insufficent_input()

Appends a continuation byte to the output byte array reference if
the continuation at input[index] is invalid.

=head3 Required arguments

=over 4

=item expected_bytes

The minimum number of bytes needed in the input.

=item output_array

The output byte array reference accepting the replacement byte.

=item input_array

The input byte array reference to test for length.

=back

=head3 Returns

True if a replacement byte was written, false otherwise.

=cut

sub replace_insufficient_input {
    my ( $expected, $byte_array_ref, $input_array_ref ) = @_;
    if ( scalar(@$input_array_ref) < $expected ) {
        push_replacement($byte_array_ref);
        return 1;
    }
    return 0;
}

=head2 Cpanel::Encoder::Cleaner::invalid_continuation()

Returns if a byte cannot be a continuation byte.

Multibyte encodings in UTF consist of a header byte and
one or more continuation bytes.  This routine tests a
byte to see if it cannot be a continuation byte.

=head3 Required arguments

=over 4

=item byte

The byte to be tested.

=back

=head3 Returns

True if the byte cannot be a continuation, false otherwise

=cut

sub invalid_continuation {
    my ($byte) = @_;
    return ( $byte & 0xc0 ) != 0x80;
}

=head2 Cpanel::Encoder::Cleaner::replace_invalid_continuation()

Appends a continuation byte to the output byte array reference if
the continuation at input[index] is invalid.

The return code indicates if a replacement byte was written.

=head3 Required arguments

=over 4

=item index

The continuation byte to check, as an offset from the input.

=item output

The output byte array reference accepting the replacement byte.

=item input

The input byte array reference to test for valid continuations.

=back

=head3 Returns

True if a replacement byte was written, false otherwise.

=cut

sub replace_invalid_continuation {
    my ( $index, $result_array_ref, $input_array_ref ) = @_;
    if ( invalid_continuation( $input_array_ref->[$index] ) ) {
        push_replacement($result_array_ref);
        return 1;
    }
    return 0;
}

=head2 Cpanel::Encoder::Cleaner::get_clean_utf_string()

Returns a UTF8 string without any UTF8 encoding errors.

This routine will scan the string one byte at a time.  In
the event it discovers a byte that cannot encode a valid
UTF8 sequence it replaces that character with the UTF8
"Replacmeent Character" \x{ef}\x{bf}\x{bd}.  Valid UTF8
byte sequences are not altered.

Returns a new string, the old string is not modified.  Avoid
using this operation unless input is known to possibly contain
strings misencoded into UTF8 from non-UTF8 inputs.

=head3 Required arguments

=over 4

=item string

A string which might include UTF8 encoding errors.

=back

=head3 Returns

A string without UTF8 encoding errors.

=cut

sub get_clean_utf_string {
    my $unclean = shift;

    return undef unless defined $unclean;

    my @result = ();
    my @input  = unpack( 'C*', $unclean );

  SEQ:
    while ( ( my $array_length = @input ) != 0 ) {
        my $first_byte   = shift(@input);
        my $continuation = 0;

        # single byte UTF-8
        if ( ( $first_byte & 0x80 ) == 0x00 ) {
            push( @result, $first_byte );
            next;
        }

        # double byte UTF-8
        if ( ( $first_byte & 0xe0 ) == 0xc0 ) {
            $continuation = 1;
        }

        # triple byte UTF-8
        if ( ( $first_byte & 0xf0 ) == 0xe0 ) {
            $continuation = 2;
        }

        # quad byte UTF-8
        if ( ( $first_byte & 0xf8 ) == 0xf0 ) {
            $continuation = 3;
        }

        # pent byte UTF-8 (proposed)
        if ( ( $first_byte & 0xfc ) == 0xf8 ) {
            $continuation = 4;
        }

        # hex byte UTF-8 (proposed)
        if ( ( $first_byte & 0xfe ) == 0xfc ) {
            $continuation = 5;
        }

        if ($continuation) {
            next if ( replace_insufficient_input( $continuation, \@result, \@input ) );
            for my $byte ( 0 .. $continuation - 1 ) {
                next SEQ if ( replace_invalid_continuation( $byte, \@result, \@input ) );
            }
            push( @result, $first_byte, splice( @input, 0, $continuation ) );
            next;
        }

        #if somehow we got here, it is not UTF8
        push_replacement( \@result );
    }
    return pack( 'C*', @result );
}

1;
