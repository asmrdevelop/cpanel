package Whostmgr::Config::Restore::Base;

# cpanel - Whostmgr/Config/Restore/Base.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Restore::Base

=head1 DESCRIPTION

Base class for inter-server configuration transfer restore modules.

=head1 METHODS

The following methods are defined on this base class:

=head2 $obj = I<CLASS>->new()

Instantiates I<CLASS>.

=cut

sub new ($class) {
    return bless {}, $class;
}

#----------------------------------------------------------------------

=head2 ($ok, $msg) = I<OBJ>->restore( $PARENT_OBJ )

Perform the actual restoration.

This receives an object that
currently is an instance of L<Whostmgr::Config::Restore> but
should ideally be replaced with a “state” object that has methods
to inject data.

=cut

sub restore ( $self, $PARENT_OBJ ) {
    return $self->_restore($PARENT_OBJ);
}

#----------------------------------------------------------------------

=head1 REQUIRED SUBCLASS METHODS

Subclasses B<must> implement the following methods:

=head2 I<OBJ>->_restore( $PARENT_OBJ )

Logic for C<restore()> above.

#----------------------------------------------------------------------

=head1 OPTIONAL SUBCLASS METHODS

Subclasses B<may> implement the following:

=head2 ($status, $statusmsg, $data) = I<OBJ>->post_restore()

Logic that executes after the entire restore has run.
The returns are included in the C<post_restore> as returned from
L<Whostmgr::Config::Restore>’s C<restore()> function.

It is suggested that any overrides of this function return
the values from the base class’s implementation if there is no need
for specific return values.

=cut

use constant post_restore => ( 1, 'Successful', q<> );

1;
