package Cpanel::TaskQueue::Reader;

# cpanel - Cpanel/TaskQueue/Reader.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::TaskQueue::Reader

=head1 SYNOPSIS

    my $queue = Cpanel::TaskQueue::Reader::read_queue();
    my $sched = Cpanel::TaskQueue::Reader::read_queue();

=head1 DESCRIPTION

This module exists because L<Cpanel::StateFile> requires a (write) lock just
to read the datastores. In certain applications it’s desirable to read these
files with minimal overhead, which this module does.

It is desirable that eventually L<Cpanel::StateFile> will provide its own
lightweight read functions, which will obviate the need for this module.

=cut

use Cpanel::JSON ();

#for tests to overwrite
our $QUEUE_FILE = '/var/cpanel/taskqueue/servers_queue.json';
our $SCHED_FILE = '/var/cpanel/taskqueue/servers_sched.json';

#Try to read the queue for one minute before timing out.
use constant TIMEOUT => 60;

=head1 FUNCTIONS

=head2 read_queue()

Reads the queue data from the filesystem and returns its contents
as a data structure. The structure returned is the 3rd member of the
top-level array in the file; for more details see the current state
of L<Cpanel::TaskQueue> and related modules.

The internals of this are intended to compensate for the fact that,
as of this writing, L<Cpanel::StateFile> doesn’t cleanly replace one
valid file with another: if the contents are invalid, we reread the
file until we get something that’s valid (up to an unspecified timeout).

=cut

sub read_queue {
    return _read($QUEUE_FILE);
}

=head2 read_sched()

Similar to C<read_queue()> but for the task schedule (i.e., future tasks)
rather than the task queue (i.e., stuff to do right away).

=cut

sub read_sched {
    return _read($SCHED_FILE);
}

sub _read {
    my ($path) = @_;

    local $@;

    my $time_to_stop = time() + TIMEOUT();
    {
        #Keep trying …
        my $load = _load($path);
        return $load if $load;

        redo if time() < $time_to_stop;
    }

    die sprintf( "The system did not retrieve valid contents from “$path” within %d seconds.", TIMEOUT() );
}

sub _load {
    my ($path) = @_;

    return eval { Cpanel::JSON::LoadFile($path)->[2] };
}

=head2 get_status_for_taskid( $id )

    get_status_for_taskid( "TQ:TaskQueue:16614" )
        or return 'not found';

Returns the current status for a task for a specific id.

Possible returns values are:

=over

=item 'processing'

Currently processing the task.

=item 'waiting'

Waiting to process the task.

=item 'scheduled'

Task is scheduled.

=item undef

Task not found.

=back

=cut

sub get_status_for_taskid ($id) {

    # 1. look in the queue
    if ( my $queue = read_queue() ) {
        return 'processing' if _task_is_in_queue( $queue->{processing_queue}, $id );
        return 'waiting'    if _task_is_in_queue( $queue->{waiting_queue},    $id );
    }

    # 2. look in the sched queue
    if ( my $queue = read_sched() ) {
        return 'scheduled' if _task_is_in_queue( $queue->{waiting_queue}, $id );
    }

    return;    # not found
}

sub _task_is_in_queue ( $queue, $id ) {
    return unless ref $queue && defined $id;

    foreach my $task ( $queue->@* ) {
        next unless defined $task->{_uuid};
        return 1 if $task->{_uuid} eq $id;
    }

    return;
}

1;
