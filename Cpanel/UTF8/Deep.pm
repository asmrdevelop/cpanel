package Cpanel::UTF8::Deep;

# cpanel - Cpanel/UTF8/Deep.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::UTF8::Deep

=head1 SYNOPSIS

    my %from_cpan = (
        "épée" => [ 'föo', 'bàr' ],
    );

    my $cloned_hr = Cpanel::UTF8::Deep::decode_clone(\%from_cpan);

At this point, C<$cloned_hr> will be all decoded/byte strings, suitable
for use in most parts of cPanel & WHM.

To send that back to the CPAN module you can do:

    my $to_cpan_hr = Cpanel::UTF8::Deep::encode($cloned_hr);

=head1 DESCRIPTION

This module contains logic for mass UTF-8 decode/encode operations on
data structures. This is useful if, e.g., you’re talking to CPAN modules
that work with decoded strings.

=head1 OF CLONING AND CLOBBERING

Take care whether the function you use preserves the source or
alters it!

=cut

#----------------------------------------------------------------------

use Data::Rmap ();

use Cpanel::UTF8::Strict ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $decoded = decode_clone($INPUT)

Clones $INPUT and returns an identical structure with all non-reference
scalars UTF-8-decoded. $INPUT itself is not affected in any way (even
if it’s a reference to a data structure).

Useful if you need to send a data structure to something that expects
character strings.

=cut

sub decode_clone ($whatsit) {
    _mutate_scalars_deep_clone(
        \$whatsit,
        \&Cpanel::UTF8::Strict::decode,
    );

    return $whatsit;
}

=head2 $encoded = encode($INPUT)

I<Sort> of the inverse of C<decode_clone()>—UTF-8-encodes all non-reference
scalars in $INPUT—but reserves the right to mutate $INPUT.

Useful if you need to receive a data structure from something that emits
character strings (and that “something” doesn’t care about the actual
structure).

=cut

sub encode ($whatsit) {
    if ( ref $whatsit ) {
        Data::Rmap::rmap_all(
            sub {
                if ( !ref ) {
                    utf8::encode($_) if $_;
                }
                elsif ( ref eq 'HASH' ) {
                    my %copy;
                    @copy{ map { utf8::encode($_); $_ } keys %$_ } = values %$_;

                    $_ = \%copy;
                }
            },
            $whatsit,
        );
    }
    elsif ($whatsit) {
        utf8::encode($whatsit);
    }

    return $whatsit;
}

# Potentially useful on its own: applies an arbitrary transform to
# all scalars and hash keys in $$scalar_ref.
sub _mutate_scalars_deep_clone ( $scalar_ref, $cr ) {

    if ( ref $$scalar_ref ) {
        Data::Rmap::rmap_all(
            sub {
                if ( !ref ) {
                    $cr->($_) if $_;
                }
                elsif ( ref eq 'HASH' ) {
                    my %copy;
                    @copy{ map { $cr->($_); $_ } keys %$_ } = values %$_;

                    $_ = \%copy;
                }
                elsif ( ref eq 'ARRAY' ) {
                    $_ = [@$_];
                }
                elsif ( ref eq 'SCALAR' ) {
                    $_ = \do { my $v = $$_ };
                }
            },
            $$scalar_ref,
        );
    }
    elsif ($$scalar_ref) {
        $cr->($$scalar_ref);
    }

    return;
}

1;
