package Cpanel::TaskQueue::Base;

# cpanel - Cpanel/TaskQueue/Base.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskQueue::Base

=head1 DESCRIPTION

This class contains common logic for L<Cpanel::TaskQueue>
and L<Cpanel::TaskQueue::Scheduler>.

=head1 METHODS

=head2 $guard = I<OBJ>->do_under_guard( $TODO_CR )

This runs $TODO_CR->( I<OBJ> ) under a L<Cpanel::StateFile::Guard> lock
and returns that lock object.

Nested calls to this function will reuse (and return) the existing lock;
i.e., no 2nd lock will be created.

Note that L<Cpanel::StateFile::Guard>’s destructor logic neatly makes it
so that if you call this function in void context, any lock that this
function created is properly released at the end.

=cut

sub do_under_guard {
    my ( $self, $todo_cr ) = @_;

    local $self->{'_guard'} = $self->_disk_state()->synch() if !$self->{'_guard'};

    $todo_cr->($self);

    return $self->{'_guard'};
}

1;
