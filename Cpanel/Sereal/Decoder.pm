package Cpanel::Sereal::Decoder;

# cpanel - Cpanel/Sereal/Decoder.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Sereal::Decoder

=head1 SYNOPSIS

    my $decoder = Cpanel::Sereal::Decoder::create();

    # .. and now use $decoder as an ordinary Sereal decoder object.

=head1 DESCRIPTION

L<Sereal::Decoder>’s defaults conduce to environments where data originates
from trusted sources. For public APIs, though, we need to restrict what the
decoder accepts. This module provides easily-reusable logic for that.

=cut

#----------------------------------------------------------------------

use Sereal::Decoder ();

my %REQUIRED_OPTIONS = (

    # Avoid destructor-execution attacks.
    refuse_objects => 1,

    # Likely redundant with “refuse_objects” but can’t hurt.
    no_bless_objects => 1,

    # Sereal’s compression isn’t safe for externally-sourced documents.
    refuse_snappy => 1,

    # Prevent invalid upgraded Perl strings.
    validate_utf8 => 1,

    # Avoid excessive recursion.
    max_recursion_depth => 100,
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $obj = create()

Returns a L<Sereal::Decoder> instance that’s safe to use to accept
externally-sourced input.

=cut

sub create {
    return Sereal::Decoder->new( \%REQUIRED_OPTIONS );
}

1;
