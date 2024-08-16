package Cpanel::SSL::cPStore::90Day::FetchError;

# cpanel - Cpanel/SSL/cPStore/90Day/FetchError.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::cPStore::90Day::FetchError

=head1 SYNOPSIS

See L<Cpanel::SSL::cPStore::90Day>.

=head1 DESCRIPTION

This class represents an error parse from Cpanel::SSL::cPStore::90Day.

=cut

#----------------------------------------------------------------------

use Class::XSAccessor (
    constructor => 'new',
    getters     => [
        'category',
        'is_error',
        'is_final',
        'type',
        'message',
    ],
);

use overload (
    q<""> => \&to_string,
);

#----------------------------------------------------------------------

=head1 ACCESSORS

=over

=item * C<is_error> - Boolean; indicates whether $ERROR indicates
that something is wrong.

=item * C<is_final> - Boolean; indicates whether the caller should
give up on this certificate order.

=item * C<category> - One of the error category constants from
L<Cpanel::SSL::cPStore::90Day>.

=back

=cut

=head1 OTHER METHODS

=head2 $str = I<OBJ>->to_string()

Returns a string that represents the error as cPStore gave it.

=cut

sub to_string ($self) {
    return sprintf( 'Received error “%s” from cPanel Store (%s)', $self->type(), $self->message() );
}

1;
