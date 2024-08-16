package Cpanel::SSL::DynamicDNSCheck::Item;

# cpanel - Cpanel/SSL/DynamicDNSCheck/Item.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DynamicDNSCheck::Item

=head1 DESCRIPTION

This is an accessor class for the results of
L<Cpanel::SSL::DynamicDNSCheck>’s C<get_report_for_user()>.

=cut

#----------------------------------------------------------------------

use Class::XSAccessor (
    getters => [
        'domain',
        'certificate',
    ],
);

#----------------------------------------------------------------------

=head1 ACCESSORS

=over

=item * C<domain> - a dynamic DNS domain name.

=item * C<certificate> - either undef (no usable certificate)
or a L<Cpanel::SSL::Objects::Certificate> instance.

=back

=head1 CLASS METHODS

=head2 $obj = I<CLASS>->adopt( $ref )

“Adopts” an existing reference into I<CLASS>.

=cut

sub adopt ( $class, $ref ) {
    return bless $ref, $class;
}

1;
