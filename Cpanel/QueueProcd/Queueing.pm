package Cpanel::QueueProcd::Queueing;

# cpanel - Cpanel/QueueProcd/Queueing.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::QueueProcd::Queueing - queueprocd’s logic to manage a queue

=head1 SYNOPSIS

    use Cpanel::QueueProcd::Queueing ();

    Cpanel::QueueProcd::Queueing::queue_process_next_task($queue, $logger);

=cut

use Cpanel::QueueProcd::Global  ();
use Cpanel::QueueProcd::Storage ();

=head1 FUNCTIONS

=head2 $ok = queue_process_next_task($queue, $logger)

Attempt to process tasks in the queue.  If attempting to process
the task generates an exception, we retry and then remove the
task.  This function is smart enough to check for deferrals tasks
that are broken enough to cause an exception when trying to move
them back to the processing queue.

Returns 1 on success or 0 on failure.

=cut

sub queue_process_next_task {
    my ( $queue, $logger ) = @_;

    Cpanel::QueueProcd::Global::set_status_msg('process next queued task');

    local $@;

    eval { $queue->process_next_task(); };

    if ($@) {

        # The task generated an exception.
        # Lets warn
        warn;

        # and try again or remove
        return _retry_or_unqueue_next_task_if_it_throws( $queue, $logger );
    }

    return 1;
}

sub _retry_or_unqueue_next_task_if_it_throws {
    my ( $queue, $logger ) = @_;

    # The disk state is now inconstant
    # due to process_next_task throwing.
    # we must force a re-read from disk
    Cpanel::QueueProcd::Storage::force_read_next_synch($queue);

    # This time we save the task before
    # trying again
    my $next_task_after_first_failure = $queue->peek_next_task();

    if ( !$next_task_after_first_failure ) {
        return _check_for_failing_deferrals( $queue, $logger );
    }

    eval { $queue->process_next_task(); };

    if ($@) {
        my $second_exception = $@;

        # The disk state is now inconstant
        # due to process_next_task throwing.
        # we must force a re-read from disk
        Cpanel::QueueProcd::Storage::force_read_next_synch($queue);

        my $next_task_after_second_failure = $queue->peek_next_task();

        if ( !$next_task_after_second_failure ) {
            return _check_for_failing_deferrals( $queue, $logger );
        }

        # Two failures.  If its the same task we are
        # in a stuck state and we need to remove
        # the task from the queue so we can
        # move on to the next one and avoid being
        # stuck forever.
        elsif ( $next_task_after_first_failure->uuid() eq $next_task_after_second_failure->uuid() ) {
            $logger->warn( 'The task [' . $next_task_after_first_failure->full_command() . "] failed multiple times because $second_exception. Removing task." );
            $queue->unqueue_task( $next_task_after_second_failure->uuid() );
            return 0;
        }

    }

    return 1;
}

sub _check_for_failing_deferrals {
    my ( $queue, $logger ) = @_;

    # There is no public method to clear the deferrals
    # so we have to dig inside :(

    eval { $queue->_process_deferrals(); };

    if ($@) {
        warn;
        my $ex    = $@;
        my $guard = $queue->{disk_state}->synch();
        foreach my $task ( @{ $queue->{deferral_queue} } ) {
            $logger->warn( 'The deferred task [' . $task->full_command() . "] failed multiple times because $ex. Removing task." );
        }
        $queue->{deferral_queue} = [];
        $guard->update_file();
        return 0;
    }

    return 0;
}

1;
