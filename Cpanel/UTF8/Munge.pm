package Cpanel::UTF8::Munge;

# cpanel - Cpanel/UTF8/Munge.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::UTF8::Munge

=head1 SYNOPSIS

    my $sanitized = Cpanel::UTF8::Munge::munge($wonky_stuff);

=head1 DESCRIPTION

Sometimes you have a string that contains a mix of UTF-8 and binary data.
You might also want to print that string to a UTF-8 terminal; in that case,
that binary data is going to be problematic.

This module implements logic to simplify that task.

=cut

#----------------------------------------------------------------------

use Unicode::UTF8 ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $out = munge($INPUT)

Takes in a string and returns a string with the following transforms:

=over

=item * All backslashes are doubled.

=item * All non-UTF-8 sequences, ASCII control bytes, and DEL characters
are replaced with C<\xNN> escapes.

=back

The result will, by definition, be valid UTF-8 and thus safe for printing
to UTF-8 terminals. (It will B<NOT> necessarily be valid ASCII.)

=cut

sub munge ($input) {
    my @invalid;

    my $unicode = do {
        no warnings 'utf8';    ## no critic qw(NoWarn)

        Unicode::UTF8::decode_utf8(
            $input,
            sub {
                my ( $octets, undef, $pos ) = @_;

                push @invalid, [ $pos, $octets ];

                return 'x' x length $octets;
            },
        );
    };

    my $output = Unicode::UTF8::encode_utf8($unicode);
    $output =~ s<\\><\\\\>g;

    for my $invalid_ar ( reverse @invalid ) {
        my $new = $invalid_ar->[1];
        $new =~ s<(.)><_to_hex($1)>emsg;

        substr( $output, $invalid_ar->[0], length $invalid_ar->[1] ) = $new;
    }

    # Handle control bytes:
    $output =~ s<([\0-\x{1f}\x{7f}])><_to_hex($1)>emsg;

    return $output;
}

sub _to_hex ($byte) {
    return sprintf '\x%02X', ord $byte;
}

1;
