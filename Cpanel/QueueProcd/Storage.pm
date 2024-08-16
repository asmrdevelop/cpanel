package Cpanel::QueueProcd::Storage;

# cpanel - Cpanel/QueueProcd/Storage.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::QueueProcd::Storage - queueprocd storage interaction logic

=head1 SYNOPSIS

    use Cpanel::QueueProcd::Storage ();

    Cpanel::QueueProcd::Storage::force_read_next_synch($queue_or_sched);

=cut

=head1 FUNCTIONS

=head2 force_read_next_synch( QUEUE_OR_SCHEDULER )

Takes either a L<Cpanel::TaskQueue> or L<Cpanel::TaskQueue::Scheduler>
instance and sets the object to reread its data from storage.

=cut

sub force_read_next_synch {
    my ($taskqueue_obj) = @_;

    # There is no public method to reset the mtime
    # to force read to we have to dig inside.
    $taskqueue_obj->{disk_state}{file_mtime} = 0;

    return;
}

1;
