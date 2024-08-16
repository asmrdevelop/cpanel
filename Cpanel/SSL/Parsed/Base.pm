package Cpanel::SSL::Parsed::Base;

# cpanel - Cpanel/SSL/Parsed/Base.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Parsed::Base

=head1 SYNOPSIS

    $parsed->key_algorithm();

    $parsed->modulus()
    $parsed->public_exponent();

    $parsed->ecdsa_curve_name();
    $parsed->ecdsa_public();

=head1 DESCRIPTION

This base class provides accessors for the members of the hashes that
L<Cpanel::SSL::Utils>’s parse functions returns.

=head1 ACCESSORS

=over

=item * C<key_algorithm>

=item * C<modulus> and C<public_exponent>

=item * C<ecdsa_curve_name> and C<ecdsa_public>

=back

=cut

#----------------------------------------------------------------------

use Class::XSAccessor (
    getters => [
        'key_algorithm',

        'public_exponent',
        'modulus',

        'ecdsa_curve_name',
        'ecdsa_public',
    ],
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->adopt( $REFERENCE )

C<bless()>es $REFERENCE into I<CLASS>. This relieves calling code of the
need to C<bless()> directly, which is rather “code-smelly” and can
create false-positives in linting tools.

As a convenience, this returns $REFERENCE.

=cut

sub adopt ( $class, $ref ) {
    return bless $ref, $class;
}

=head2 I<OBJ>->TO_JSON()

cf. L<JSON>

=cut

sub TO_JSON ($self) {
    return {%$self};
}

1;
