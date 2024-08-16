package Cpanel::Sereal::Encoder;

# cpanel - Cpanel/Sereal/Encoder.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Sereal::Encoder

=head1 SYNOPSIS

    my $encoder = Cpanel::Sereal::Encoder::create();

    # .. and now use $encoder as an ordinary Sereal encoder object.

=head1 DESCRIPTION

This module configures a L<Sereal::Encoder> instance such that it will refuse
to send anything that a L<Cpanel::Sereal::Decoder> instance will reject.

=head1 COMPATIBILITY WITH JSON

Many Perl JSON encoders will, when given a blessed object, call that object’s
C<TO_JSON()> method if such exists. This module doesn’t implement that;
if you need it (e.g., to replace JSON with Sereal), look at
L<Cpanel::JSON::Sanitize>.

=cut

#----------------------------------------------------------------------

use Sereal::Encoder ();

my %REQUIRED_OPTIONS = (

    # Avoid destructor-execution attacks.
    croak_on_bless => 1,
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $obj = create()

Returns a L<Sereal::Encoder> instance configured as described above.

=cut

sub create {
    return Sereal::Encoder->new( \%REQUIRED_OPTIONS );
}

1;
