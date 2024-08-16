package Cpanel::TaskQueue::Manager;

# cpanel - Cpanel/TaskQueue/Manager.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 Cpanel::TaskQueue::Manager

Cpanel::TaskQueue::Manager - Tools for managing the task queue

=head1 SYNOPSIS

    use Cpanel::TaskQueue::Manager ();

    Cpanel::TaskQueue::Manager::run_all_tasks();

=cut

use cPstrict;

use Try::Tiny;

my $logger_object;

our $WAIT_TIMEOUT = 30 * 60;    # 30 minutes

# $WAIT_TIMEOUT:
# The number of seconds we should wait before giving up
# on waiting for the taskqueue.

my $WAIT_INTERVAL = 0.025;

# $WAIT_INTERVAL:
# This is the time we wait between checking to see if the
# taskqueue is empty.

# Only TaskQueue modules allowed for memory reasons
use Cpanel::Inotify              ();
use Cpanel::TaskQueue            ();    # NOTE: This code assumes you've done the critical imports already.
use Cpanel::TaskQueue::Scheduler ();    # NOTE: This code assumes you've done the critical imports already.

my $file_ext = 'json';

sub queue_dir { return '/var/cpanel/taskqueue' }

{
    my @task_queues_cache;

    sub get_task_queues {
        return @task_queues_cache if (@task_queues_cache);
        opendir( my $dirfh, queue_dir() ) or die( "Can't read directory " . queue_dir() );
        while ( my $file = readdir $dirfh ) {
            next unless $file =~ m/^(.+)_queue\.$file_ext$/;
            push @task_queues_cache, "$1";
        }
        return @task_queues_cache;
    }

    my @schedules_cache;

    sub get_schedule_queues {
        return @schedules_cache if (@schedules_cache);
        opendir( my $dirfh, queue_dir() ) or die( "Can't read directory " . queue_dir() );
        while ( my $file = readdir $dirfh ) {
            next unless $file =~ m/^(.+)_sched\.$file_ext$/;
            push @schedules_cache, "$1";
        }
        return @schedules_cache;
    }
}

sub set_logger_object {
    ($logger_object) = @_;

    return $logger_object;
}

my %_task_queue_object_cache;

sub task_queue_object {
    my ($queue) = @_;
    $queue or die("Queue name not passed to task_queue_object()");
    if ( $_task_queue_object_cache{$queue} ) {
        $_task_queue_object_cache{$queue}->{disk_state}->synch();
        return $_task_queue_object_cache{$queue};
    }

    my $queue_dir = queue_dir();
    -e "$queue_dir/${queue}_queue.$file_ext" or die("No such task queue '$queue'");

    return ( $_task_queue_object_cache{$queue} = Cpanel::TaskQueue->new( { cache_dir => $queue_dir, ( $logger_object ? ( logger => $logger_object ) : () ), name => $queue } ) );
}

my %_scheduler_object_cache;

sub scheduler_object {
    my ($queue) = @_;
    $queue or die("Queue name not passed to task_queue_object()");
    if ( $_scheduler_object_cache{$queue} ) {
        $_scheduler_object_cache{$queue}->{disk_state}->synch();
        return $_scheduler_object_cache{$queue};
    }
    my $queue_dir = queue_dir();
    -e "$queue_dir/${queue}_sched.$file_ext" or die("No such scheduler queue '$queue'");

    return ( $_scheduler_object_cache{$queue} = Cpanel::TaskQueue::Scheduler->new( { cache_dir => $queue_dir, ( $logger_object ? ( logger => $logger_object ) : () ), name => $queue } ) );
}

sub delete_matching_tasks {
    my ($regex) = @_;
    my $matched = 0;
    foreach my $queue_name ( get_task_queues() ) {
        my $obj = task_queue_object($queue_name);
        foreach my $task_item ( @{ $obj->{'queue_waiting'} } ) {
            if ( $task_item->full_command() =~ $regex ) {
                $obj->unqueue_task( $task_item->uuid() );
                $matched++;
            }
        }
        $obj = scheduler_object($queue_name);
        foreach my $task_item ( @{ $obj->{'time_queue'} } ) {
            if ( $task_item->{'task'}->full_command() =~ $regex ) {
                $obj->unschedule_task( $task_item->{'task'}->uuid() );
                $matched++;
            }
        }
    }
    return $matched;
}

sub queued_tasks {
    my @tasks;
    foreach my $queue ( get_task_queues() ) {
        push @tasks, task_queue_object($queue)->_list_of_all_tasks();
    }

    return @tasks;
}

sub get_deferred {
    foreach my $queue_name ( get_task_queues() ) {
        my $queue = task_queue_object($queue_name);
        return $queue->{defer_obj} if $queue->{defer_obj} && %{ $queue->{defer_obj} };
    }
    return {};
}

sub clear_deferred {
    foreach my $queue_name ( get_task_queues() ) {
        my $obj   = task_queue_object($queue_name);
        my $guard = $obj->{disk_state}->synch();
        $obj->{'defer_obj'} = {};
        $guard->update_file();
    }
    return;
}

sub scheduled_tasks {
    my @tasks;

    foreach my $queue ( get_schedule_queues() ) {
        my $obj = scheduler_object($queue);
        if ( ref $obj->{'time_queue'} eq 'ARRAY' ) {
            foreach my $task_item ( @{ $obj->{'time_queue'} } ) {
                $task_item->{'queue_name'} = $queue;    # For later reference.
                push @tasks, $task_item;
            }
        }
    }

    return @tasks;
}

sub count_running_tasks {
    my $tasks;
    foreach my $queue ( get_task_queues() ) {
        $tasks += task_queue_object($queue)->how_many_in_process();
    }

    return $tasks;
}

=head2 @lists = _get_snapshot()

Returns a list of array references:

=over

=item * Tasks being processed

=item * Tasks in “waiting” status

=item * Deferred tasks

=item * Tasks scheduled for later

=back

The first 3 elements are arrayrefs of L<Cpanel::TaskQueue::Task> instances.

The forth element is a arrayref in the format:

  [
    {
      'time' => '1234', # Scheduled time
      'task' => <Cpanel::TaskQueue::Task>
    }
  ]

=cut

sub _get_snapshot {
    my ( @processing, @waiting, @deferred );

    #Avoid Cpanel::Context for memory
    die 'list content only!' if !wantarray;

    my @scheduled = scheduled_tasks();
    foreach my $queue ( get_task_queues() ) {
        my $snap = task_queue_object($queue)->snapshot_task_lists();
        push @processing, @{ $snap->{'processing'} };
        push @waiting,    @{ $snap->{'waiting'} };
        push @deferred,   @{ $snap->{'deferred'} };
    }

    return ( \@processing, \@waiting, \@deferred, \@scheduled );
}

sub has_work_todo {
    return scalar queued_tasks() || scalar scheduled_tasks();
}

sub list_work_todo {
    return ( queued_tasks(), scheduled_tasks() );
}

our $OUTPUT_TIMEOUT = 20;

sub _output_message ($msg) {
    state $last_message_at  = 0;
    state $last_message_str = '';

    chomp $msg if defined $msg;
    return unless length $msg;

    my $now = time();

    # only display the same message once in a while
    return if $last_message_str eq $msg && ( $now - $last_message_at ) < $OUTPUT_TIMEOUT;

    $last_message_at  = $now;
    $last_message_str = $msg;

    _say($msg);

    return;
}

sub _say ($msg) {    # for testing purpose
    return say($msg);
}

sub default_pid_file {
    return '/var/run/queueprocd.pid';
}

sub queueprocd_pid {
    my ($pid_file) = @_;
    $pid_file ||= default_pid_file();

    open( my $pid_fh, '<', $pid_file ) or die("queueprocd isn't running?");
    my $pid = <$pid_fh>;
    close $pid_fh;
    chomp $pid;
    return $pid;
}

sub kick_queueprocd {
    my ($pid_file) = @_;    # Optional

    return if $ENV{'CPANEL_BASE_INSTALL'};

    my $pid = queueprocd_pid($pid_file);
    $pid or die("$pid_file is present but has no pid in it?");

    return kill( 'USR1', $pid );
}

sub wait_for_task_queue {
    my @disk_state_files;
    my $queue_dir = queue_dir();
    foreach my $queue_name ( get_task_queues() ) {
        push @disk_state_files, "$queue_dir/${queue_name}_queue.$file_ext";
    }
    foreach my $queue_name ( get_schedule_queues() ) {
        push @disk_state_files, "$queue_dir/${queue_name}_sched.$file_ext";
    }

    #We don’t care about failures because they likely
    #just mean that the disk_state_file was replaced.
    try {
        my $inotify_obj = Cpanel::Inotify->new( flags => ['NONBLOCK'] );
        foreach my $disk_state_file (@disk_state_files) {
            $inotify_obj->add( $disk_state_file, flags => [ 'ATTRIB', 'DELETE_SELF' ] );
        }

        vec( my $rin, $inotify_obj->fileno(), 1 ) = 1;

        select( $rin, undef, undef, $WAIT_INTERVAL );
    };

    return;
}

=head2 run_all_tasks

Run all the tasks in the task queue in order.  If there are tasks
scheduled in the future, they are rescheduled for now.

This function returns the number of times it ran the loop to wait for tasks or
-1 on timeout.

It is advisable to avoid calls to this function once there are active accounts
on the system as it will accelerate everything in the task queue to happen as
soon as possible.

While cPanel regularly does this in our test plans, the task queue system allows
for plugins which may not have planned for having their tasks accelerated.

=cut

sub run_all_tasks {
    my ($pid_file) = @_;    # Optional

    my $queue_count = scalar queued_tasks();
    my @schedule_objects;
    my $schedule_count = 0;
    foreach my $queue ( get_schedule_queues() ) {
        my $obj = scheduler_object($queue);
        $schedule_count += scalar @{ $obj->{'time_queue'} };
        push @schedule_objects, $obj;
    }

    return 0 if !$queue_count && !$schedule_count;

    my $work = $queue_count + $schedule_count;

    if ($schedule_count) {
        _reschedule_all_pending_tasks_for_now(@schedule_objects);
    }

    require Cpanel::Alarm;

    my $reached_timeout = 0;
    my $alarm           = Cpanel::Alarm->new(
        $WAIT_TIMEOUT,
        sub {
            _output_message("Timed out waiting for tasks after $WAIT_TIMEOUT second(s).");

            $reached_timeout = 1;
        }
    );

    my ( $running_ref, $waiting_ref, $deferred_ref, $scheduled_ref );
    my $tried = 0;
    while ( !$reached_timeout ) {
        ( $running_ref, $waiting_ref, $deferred_ref, $scheduled_ref ) = _get_snapshot();

        $work = scalar @$running_ref + scalar @$waiting_ref + scalar @$deferred_ref + scalar @$scheduled_ref;

        last if !$work;

        $tried++;

        if ( $tried == 1 || !( $tried % 8 ) ) {    # Print every 2 seconds if queue is not clear.
            my $msg = ( $ENV{'T2_HARNESS_ACTIVE'} ? "$0: " : '' ) . "Waiting for $work task" . ( $work > 1 ? 's' : '' ) . " to complete: ";
            $msg .= join(
                '; ',
                grep { $_ } (
                    _format_message( 'running',   [ map { $_->full_command } @$running_ref ] ),
                    _format_message( 'waiting',   [ map { $_->full_command } @$waiting_ref ] ),
                    _format_message( 'deferred',  [ map { $_->full_command } @$deferred_ref ] ),
                    _format_message( 'scheduled', [ map { $_->{'task'}->full_command } @$scheduled_ref ] )
                )
            );
            _output_message($msg);
        }

        if (@$scheduled_ref) {
            if ( grep { $_->{'time'} != 1 } @$scheduled_ref ) {    # New tasks sometimes get added so we need to reschedule if they do
                _reschedule_all_pending_tasks_for_now(@schedule_objects);
            }
        }

        # It is possible that the next read of the Cpanel::TaskQueue file
        # will be cached because the size and mtime have both remained the
        # same even though there was an updated in the same second. To avoid
        # this problem we force a read of the file just like we do
        # in queueprocd
        require Cpanel::QueueProcd::Storage;
        Cpanel::QueueProcd::Storage::force_read_next_synch($_) for @schedule_objects;

        wait_for_task_queue();
    }

    return $reached_timeout ? -1 : $tried;
}

sub _format_message {
    my ( $type, $items ) = @_;
    return '' unless @$items;
    return "$type (" . join( ", ", map { s/^\s*(.*\S)\s*$/$1/r } @$items ) . ')';
}

sub _reschedule_all_pending_tasks_for_now {
    my (@schedule_objects) = @_;

    # Reschedule all pending tasks for now
    foreach my $obj (@schedule_objects) {
        my $guard = $obj->{disk_state}->synch();
        for ( @{ $obj->{time_queue} } ) {
            $_->{'time'} = 1;
        }
        $guard->update_file();
    }
    return 1;
}

1;
