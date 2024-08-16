package Cpanel::Pkgacct::Component;

# cpanel - Cpanel/Pkgacct/Component.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Pkgacct::Component

=head1 DESCRIPTION

This is a base class for pkgacct component modules.

=head1 INHERITANCE

Lamentably, this module inherits from L<Cpanel::Pkgacct>. This was
a design mistake because it complicates mocking; a subclass of
L<Cpanel::Pkgacct> will still instantiate L<Cpanel::Pkgacct::Component>
instances, which in turn still subclass the base L<Cpanel::Pkgacct>
class, so any overrides in the L<Cpanel::Pkgacct> subclass will be missing
from the component modules.

To undo this mistake would be a project unto itself. In the meantime,
instead of using methods from L<Cpanel::Pkgacct> in component modules,
write wrapper methods that call into methods of the the component object’s
C<pkgacct_obj> attribute. That way, if C<pkgacct_obj> is an instance of
its own subclass of C<Cpanel::Pkgacct> (as is useful, e.g., in testing),
that subclass’s override logic will be available to the component
object.

See C<get_cpuser_data()> for an example.

=cut

#----------------------------------------------------------------------

# XXX Inheriting from Cpanel::Pkgacct was a mistake. To undo it would be a
# project unto itself, though.
#
# In the meantime, please don’t write new component logic that depends on
# methods inherited from Cpanel::Pkgacct; instead, write a method that
# calls into a method on the “pkgacct_obj” attribute. See get_cpuser_data()
# for an example.
use parent 'Cpanel::Pkgacct';

# NB: This can’t use constant.pm because B::C-compiled code
# doesn’t have Cpanel::Pkgacct::_required_properties() defined yet,
# though interpreted code does.
sub _required_properties {
    return (
        'pkgacct_obj',
        __PACKAGE__->SUPER::_required_properties(),
    );
}

#----------------------------------------------------------------------

=head1 METHODS

As discussed above in L</INHERITANCE>, this module unfortunately
inherits from L<Cpanel::Pkgacct>; however, you should avoid use of this
inheritance for reasons discussed above.

Here are the methods that L<Cpanel::Pkgacct::Component> defines and
are safe to use in new code:

=head2 I<OBJ>->get_cpuser_data()

See the method of the same name in L<Cpanel::Pkgacct>.

=cut

sub get_cpuser_data {
    my ($self) = @_;

    return $self->get_attr('pkgacct_obj')->get_cpuser_data();
}

1;
