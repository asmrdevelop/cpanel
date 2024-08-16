package Cpanel::TaskQueue::Scheduler::DupeSupport;

# cpanel - Cpanel/TaskQueue/Scheduler/DupeSupport.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::TaskQueue::Scheduler';

# This module provides duplicate support for Cpanel::TaskQueue::Scheduler
# like Cpanel::TaskQueue since the original did not resolve duplicates
sub _schedule_the_task_under_lock {
    my ( $self, $time, $task ) = @_;

    $self->_process_overrides($task);
    return if $self->_is_duplicate_command($task);

    my $item = { time => $time, task => $task };

    # if the list is empty, or time after all in list.
    if ( !@{ $self->{time_queue} } || $time >= $self->{time_queue}->[-1]->{time} ) {
        push @{ $self->{time_queue} }, $item;
    }
    elsif ( $time < $self->{time_queue}->[0]->{time} ) {

        # schedule before anything in the list
        unshift @{ $self->{time_queue} }, $item;
    }
    else {

        # find the correct spot in the list.
        foreach my $i ( 1 .. $#{ $self->{time_queue} } ) {
            next unless $self->{time_queue}->[$i]->{time} > $time;
            splice( @{ $self->{time_queue} }, $i, 0, $item );
            last;
        }
    }

    return $task->uuid();
}

sub _schedule_the_task {
    my ( $self, $time, $task ) = @_;

    my $guard = $self->{disk_state}->synch();

    my $uuid = $self->_schedule_the_task_under_lock( $time, $task );

    $guard->update_file();

    return $uuid;
}

# Test whether the supplied task descriptor duplicates any in the queue.
sub _is_duplicate_command {
    my ( $self, $task ) = @_;

    my $proc = Cpanel::TaskQueue::_get_task_processor($task) or die "Cannot find a processor module for “" . $task->full_command() . "”";    # PPI USE OK - Already loaded

    return defined Cpanel::TaskQueue::_first( sub { $proc->is_dupe( $task, $_->{'task'} ) }, reverse @{ $self->{time_queue} } );             # PPI USE OK - Already loaded
}

sub _process_overrides {
    my ( $self, $task ) = @_;
    my $proc = Cpanel::TaskQueue::_get_task_processor($task) or die "Cannot find a processor module for “" . $task->full_command() . "”";    # PPI USE OK - Already loaded

    $self->{time_queue} = [ grep { !$proc->overrides( $task, $_->{'task'} ) } @{ $self->{time_queue} } ];

    return;
}

1;
