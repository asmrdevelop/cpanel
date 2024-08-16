package Cpanel::TaskProcessor;

# cpanel - Cpanel/TaskProcessor.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessor - Base class for use in TaskProcessor modules

=head1 SYNOPSIS

    package Cpanel::TaskProcessors::SomeModule::SomeSubModule;

    use parent 'Cpanel::TaskProcessor';

    use constant _ARGS_COUNT => 1;

    ...

=head1 DESCRIPTION

This base class handles a bit of the repetitive code that most TaskProcessor
modules require. It subclasses L<Cpanel::TaskQueue::FastSpawn>.

=cut

use parent 'Cpanel::TaskQueue::FastSpawn';

=head1 REQUIRED METHODS

=head2 I<CLASS>->_ARGS_COUNT()

Returns the number of arguments that the task should receive.
This method may be most naturally defined as a L<constant>.

=cut

=head1 METHODS

=head2 $yn = I<OBJ>->is_valid_args( TASK )

TASK is an instance of L<Cpanel::TaskQueue::Task>. The return is a
boolean that indicates whether the arguments as submitted are the correct
number of arguments for the current class.

=cut

sub is_valid_args {
    my ( $self, $task ) = @_;
    return 0 if scalar $task->args() != $self->_ARGS_COUNT();
    return 1;
}

1;
