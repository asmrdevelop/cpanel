package Cpanel::TaskQueue::ChildProcessor;

# cpanel - Cpanel/TaskQueue/ChildProcessor.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use warnings;
use base 'Cpanel::TaskQueue::Processor';

use Cpanel::Debug ();

{

    sub get_child_timeout {
        my ($self) = @_;
        return;
    }

    sub get_reschedule_delay {
        my ( $self, $task ) = @_;

        return 15 * 60;
    }

    sub retry_task {
        my ( $self, $task, $delay ) = @_;
        $delay ||= $self->get_reschedule_delay($task);

        $task->decrement_retries();
        if ( $task->retries_remaining() and $task->get_userdata('sched') ) {
            require Cpanel::TaskQueue::Scheduler;
            my $s = Cpanel::TaskQueue::Scheduler->new( { token => $task->get_userdata('sched') } );

            # This will either succeed or exception.
            $s->schedule_task( $task, { delay_seconds => $delay } );
        }

        return;
    }

    sub process_task {
        my ( $self, $task, $logger, $guard ) = @_;
        my $pid = fork();

        $logger->throw( q{Unable to start a child process to handle the '} . $task->command() . "' task\n" )
          unless defined $pid;

        # Parent returns
        return $pid if $pid;

        if ( !$guard ) {
            die __PACKAGE__ . ': expected 3 arguments to process_task($task, $logger, $guard): $guard was missing';
        }

        # Now in child
        # Ensure the child process never unlocks
        # the lock file as this should always be done
        # in the parent.
        $guard->_in_child();

        my $timeout = $self->get_child_timeout() || $task->child_timeout();
        my $oldalarm;
        eval {
            local $SIG{'CHLD'} = 'DEFAULT';
            local $SIG{'ALRM'} = sub { die "timeout detected\n"; };
            $oldalarm = alarm $timeout;
            my $normalized_full_command = $task->normalized_full_command();
            $logger->info("Executing $normalized_full_command ...") if Cpanel::Debug::log_debug();
            $self->_do_child_task( $task, $logger );
            $logger->info("... $normalized_full_command Done") if Cpanel::Debug::log_debug();
            alarm $oldalarm;
            1;
        } or do {
            my $ex = $@;
            alarm $oldalarm;
            if ( $ex eq "timeout detected\n" ) {
                eval {

                    # TODO: consider adding another timeout in case this handling
                    # locks up.
                    $self->_do_timeout($task);

                    # Handle retries
                    $self->retry_task($task);
                };

                # Don't throw, we want to exit instead.
                if ($@) {
                    $logger->warn($@);
                    exit 1;
                }
            }
            else {

                # Don't throw, we want to exit instead.
                $logger->warn($ex);
                exit 1;
            }
        };
        exit 0;
    }

    sub _do_timeout {
        my ( $self, $task ) = @_;

        return;
    }

    sub _do_child_task {
        my ( $self, $task, $logger ) = @_;

        $logger->throw("No child task defined.\n");
        return;
    }
}

1;

__END__


=head1  NAME

Cpanel::TaskQueue::ChildProcessor - Processes an individual task from the Cpanel::TaskQueue in a child process.

=head1 SYNOPSIS

    package NewTask;

    use base 'Cpanel::TaskQueue::ChildProcessor';

    sub _do_child_task {
        my ($self, $task, $logger) = @_;

        # do something exciting.

        return;
    }

    sub is_valid_args {
        my ($self, $task) = @_;
        # all args must be numeric
        return !grep { /[^-\d]/ } @{$task->args()};
    }

    # This task should take between 15-20 minutes to run, if it takes half an
    #   hour we need to fail
    sub get_child_timeout {
        my ($self) = @_;

        return 1800;
    }

=head1  DESCRIPTION

This module provides an abstraction for commands to be executed by a child
process launched from the TaskQueue. It overrides the C<process_task> method
to fork a child process and return the appropriate information back to
C<Cpanel::TaskQueue>.

In addition, the class provides automatic timeout support for the child process.

=head1 PUBLIC METHODS

This interface of this class is defined by its base class Cpanel::TaskQueue::Processor.

=over 4

=item $proc->process_task( $task, $logger )

This method has been overridden from the base class to launch a child process and
execute the C<_do_child_task> method. If the C<_do_child_task> method times out and
the Task has retries remaining, the C<ChildProcessor> will automatically reschedule
the Task for later execution. The time delay is determined by the return value of the
C<get_reschedule_delay> method.

If you plan to override this method, you are better off deriving from
C<Cpanel::TaskQueue::Procesor> and doing all of the work yourself.

=item $proc->retry_task( $task, $delay )

This method reschedules a I<task> to try again. It is called automatically when
a child process times out. However, the child process may determine that it has
failed and decide that rescheduling is necessary. This method provides a way for
the child process to easily reschedule itself. The optional I<delay> parameter
specifies how many seconds to delay before queuing the process again. It defaults
to the value returned by C<get_child_timeout>.

=item $proc->_do_child_task( $task, $logger )

This method is executed in a child process. It is provided a C<Cpanel::TaskQueue::Task>
object and a logging object. See L<Cpanel::TaskQueue/#LOGGER OBJECT>
for the interface of the C<$logger> object.

A subclass must override this method to provide the needed behavior. This method
is called after the child process has already been forked, so this subroutine
will run in the child process.

=item $proc->_do_timeout( $task )

Although you can perform any processing you want in C<_do_child_task> if your
task is successful or if you determine it has failed. This method supplies an
entry point for handling the timeout case. If your process times out, the
C<process_task> method calls C<_do_timeout> with the task description as an
argument. You can then perform cleanup or possibly retry your task.

One word of warning, the processing in this method should be relatively fast.

=item $proc->get_child_timeout()

This method should return a timeout value (in seconds) for the maximum time we
will wait for the child process to complete. Return 0 or C<undef> to use the
default value specified by the C<Cpanel::TaskQueue>.

Subclasses may override this method to return a value different than the default.

=item $proc->get_reschedule_delay( $task )

This method should return a number of seconds in the future to schedule the next
retry. The default value is 900 (15 minutes). The I<task> parameter is supplied
in case it is needed to determine the delay. This could be useful in case you
want to schedule each succeeding retry farther in the future.

Subclasses should override thius method to return a value different than the
default.

=back


=head1 DIAGNOSTICS

=over

=item C<< No child task defined. >>

Either this base class has been used directly as a processor for a command or
the C<_do_child_task> method was not overridden in a derived class.

In either case, the default behavior for C<_do_child_task> is to throw an exception.

=item C<< Failed to reschedule task. >>

Attempting to reschedule a task after timeout failed. This should never happen.

=item C<< Unable to start a child process to handle the '%s' task >>

Unable to C<fork> a child process to execute the task. Possibly too many processes
are running?

=back

=head1 CONFIGURATION AND ENVIRONMENT

Cpanel::TaskQueue::ChildProcessor requires no configuration files or environment variables.

=head1 DEPENDENCIES

None

=head1 SEE ALSO

Cpanel::TaskQueue, Cpanel::TaskQueue::Processor, Cpanel::TaskQueue::Task

=head1 INCOMPATIBILITIES

None reported.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

=head1 AUTHOR

G. Wade Johnson  C<< wade@cpanel.net >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2014, cPanel, Inc. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
