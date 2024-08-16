package Cpanel::SSL::Parsed::Certificate;

# cpanel - Cpanel/SSL/Parsed/Certificate.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Parsed::Certificate

=head1 SYNOPSIS

    $parsed->modulus()
    $parsed->ecdsa_curve_name();
    $parsed->ecdsa_public();
    $parsed->key_algorithm();

=head1 DESCRIPTION

This class provides accessors for the members of the hashes that
L<Cpanel::SSL::Utils>’s C<parse_certificate_text()> returns.

It subclasses L<Cpanel::SSL::Parsed::Base>. As of now it provides
no accessors that that base class does not.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::SSL::Parsed::Base';

use Class::XSAccessor (
    getters => [
        'not_before',
        'not_after',
        'subject',
        'issuer',
        'is_self_signed',
    ],
);

#----------------------------------------------------------------------

=head1 ACCESSORS

Besides those inherited from the base class, this class adds:

=over

=item * C<not_before> and C<not_after>

=item * C<subject> and C<issuer>

=item * C<is_self_signed>

=back

=cut

1;
