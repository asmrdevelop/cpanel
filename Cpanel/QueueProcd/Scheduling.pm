package Cpanel::QueueProcd::Scheduling;

# cpanel - Cpanel/QueueProcd/Scheduling.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::QueueProcd::Scheduling - queueprocd’s logic to manage a scheduler

=head1 SYNOPSIS

    use Cpanel::QueueProcd::Scheduling ();

    Cpanel::QueueProcd::Scheduling::scheduler_add_ready_task_into_queue($sched, $queue, $logger);

=cut

use Cpanel::QueueProcd::Global  ();
use Cpanel::QueueProcd::Storage ();

=head2 $ok = scheduler_add_ready_task_into_queue($sched, $queue, $logger)

Attempt to move any scheduled tasks that are now ready to be
processed into the task queue from the schedule queue.  If the task
fails to queue, we remove it from the schedule.

Returns 1 on success or 0 on failure.

=cut

sub scheduler_add_ready_task_into_queue {
    my ( $sched, $queue, $logger ) = @_;

    Cpanel::QueueProcd::Global::set_status_msg('process next scheduled task');

    local $@;

    eval { $sched->process_ready_tasks($queue); };

    if ($@) {
        return _handle_task_schedule_failure( $sched, $queue, $@, $logger );
    }

    return 1;
}

sub _handle_task_schedule_failure {
    my ( $sched, $queue, $ex, $logger ) = @_;

    # The disk state is now inconstant
    # due to process_ready_tasks throwing.
    # we must force a re-read from disk
    Cpanel::QueueProcd::Storage::force_read_next_synch($sched);
    Cpanel::QueueProcd::Storage::force_read_next_synch($queue);

    # See Cpanel::TaskQueue::_queue_the_task to match exception strings.
    if ( $ex =~ /^No known processor/ ) {

        # If the current task has no processor, reload all plugins.
        Cpanel::QueueProcd::Global::reload_plugins();
        $logger->warn("Plugins reloaded in case there are new ones.");

        $ex = 'there is no processor';
    }

    # Recognize bad tasks and remove the bad task.
    elsif ( $ex =~ /invalid arguments/ ) {
        $ex = 'invalid arguments';
    }
    else {
        local $@ = $ex;
        warn;

        $ex = "$ex";
    }

    return _queue_next_ready_scheduled_task_or_remove(
        $sched,
        $queue,
        $logger,
        $ex,
    );
}

sub _queue_next_ready_scheduled_task_or_remove {
    my ( $sched, $queue, $logger, $failure_message ) = @_;

    #The “next task” here is the same one that failed and got
    #us here; thus, it could be considered the scheduler’s
    #“current task”.
    my $task = $sched->peek_next_task();

    if ( defined $task ) {
        eval {
            $queue->queue_task($task);
            1;
        } or do {
            $logger->warn( 'The task [' . $task->full_command() . "] cannot be queued because $failure_message. Removing task." );
            $sched->unschedule_task( $task->uuid() );
            return 0;
        };
        return 1;
    }

    return 0;
}

1;
