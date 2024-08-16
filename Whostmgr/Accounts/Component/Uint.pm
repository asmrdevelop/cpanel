package Whostmgr::Accounts::Component::Uint;

# cpanel - Whostmgr/Accounts/Component/Uint.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Component::Uint

=head1 DESCRIPTION

A subclass of L<Whostmgr::Accounts::Component> for unsigned integers.

B<NOTE:> For historical reasons, this class’s C<type> is
C<numeric>, not C<uint> or the like.

=cut

#----------------------------------------------------------------------

use parent 'Whostmgr::Accounts::Component';

use Cpanel::Imports;

use constant _type => 'numeric';

use constant _ACCESSORS => (
    __PACKAGE__->SUPER::_ACCESSORS(),
    'minimum',
    'maximum',
);

#----------------------------------------------------------------------

=head1 ACCESSORS

(See the base class for inherited accessors.)

See L<Whostmgr::Packages::Info::Modular> for details about these:

=over

=item * C<minimum>

=item * C<maximum>

=back

=cut

use Class::XSAccessor (
    getters => [_ACCESSORS],
);

#----------------------------------------------------------------------

sub _why_invalid ( $self, $specimen ) {
    if ( $specimen =~ tr<0-9><>c ) {
        return locale()->maketext( '“[_1]” is not a nonnegative integer.', $specimen );
    }

    if ( $specimen < $self->minimum() ) {
        return locale()->maketext( '[numf,_1] is too low. The minimum value is [numf,_2].', $specimen, $self->minimum() );
    }

    if ( defined( $self->maximum() ) && ( $specimen > $self->maximum() ) ) {
        return locale()->maketext( '[numf,_1] exceeds the maximum value ([numf,_2]).', $specimen, $self->maximum() );
    }

    return undef;
}

1;
