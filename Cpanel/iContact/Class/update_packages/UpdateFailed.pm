package Cpanel::iContact::Class::update_packages::UpdateFailed;

# cpanel - Cpanel/iContact/Class/update_packages/UpdateFailed.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::iContact::Class::update_packages::UpdateFailed - iContact class for errors during package updates

=head1 SYNOPSIS

    use Cpanel::iContact::Class::update_packages::UpdateFailed;

    my @required_args = Cpanel::iContact::Class::update_packages::UpdateFailed->_required_args();

=head1 DESCRIPTION

This module is used to send iContact notifications when the update-packages script fails for any reason.
It is a subclass of C<Cpanel::iContact::Class>. This class currently only implements two functions: One
to return the names of the required arguments for the class, and one to return the arguments to be passed
to the template.

=head1 SUBROUTINES/METHODS

=cut

use cPstrict;

use parent qw(Cpanel::iContact::Class);

my @required_args = qw();

=head2 _required_args

This method returns the names of the required arguments for this class. It will call the parent class's
C<_required_args> method and add the names of the required arguments for this class to the list.

=over 2

=item Input

=over 3

=item C<Required: Class>

 This should be passed in automatically when called as a class method.

=back

=back

=over 2

=item Output

=over 3

=item C<ARRAY>

 This method returns an arrayref containing the names of the required arguments for this class.

=back

=back

=cut

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

=head2 _template_args

This method returns the arguments to be passed to the template. It will call the parent class's
C<_template_args> method and add the arguments for this class to the list.

=over 2

=item Input

=over 3

=item C<Required: Self>

 This argument is an object of this class. This should be passed in automatically when called as an
 object method.

=back

=back

=over 2

=item Output

=over 3

=item C<HASH>

 This method returns a hash containing the arguments to be passed to the template.

=back

=back

=cut

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } ( @required_args, 'origin' )
    );
}

1;
