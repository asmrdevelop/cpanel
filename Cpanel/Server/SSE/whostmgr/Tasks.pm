package Cpanel::Server::SSE::whostmgr::Tasks;

# cpanel - Cpanel/Server/SSE/whostmgr/Tasks.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf8

=head1 NAME

Cpanel::Server::SSE::whostmgr::Tasks - SSE monitor for WHM’s task queue

=head1 SYNOPSIS

    #See parent class for arguments
    my $sse_tasks = Cpanel::Server::SSE::whostmgr::Tasks->new( ... );

    $sse_tasks->run();

=head1 DESCRIPTION

This module provides two types of SSE events: C<queue-update>
and C<sched-update>.

=head1 C<queue-update> EVENTS

The payload of this event is a JSON representation of the queue.
It’s based on the result of L<Cpanel::TaskQueue>’s
C<snapshot_task_lists()> method, with each list represented as an array
of hashes. Each hash looks like:

=over

=item * C<command> - An array of the command and arguments.

=item * C<child_timeout> - Like C<snapshot_task_lists()>’s response, but
-1 is returned as undef.

=item * C<id> - Identical to C<snapshot_task_lists()>’s C<uuid> response.

=item * C<timestamp> - Identical to C<snapshot_task_lists()>’s response.

=item * C<pid> - Identical to C<snapshot_task_lists()>’s response.

=item * C<retries_remaining> - Identical to C<snapshot_task_lists()>’s response.

=back

=head1 C<sched-update> EVENTS

The payload of this event is a JSON representation of the queue.
It’s based on the result of L<Cpanel::TaskQueue::Scheduler>’s
C<snapshot_task_schedule()> method, with the return represented as an array
of hashes. Each hash looks like:

=over

=item * C<time> - Identical to C<snapshot_task_schedule()>’s response.

=item * C<task> - A hash that represents a task in the same format as
in a C<queue-update> event.

=back

=cut

use parent qw( Cpanel::Server::SSE::whostmgr );

use Cpanel::Inotify ();
use Cpanel::Locale::Lazy 'lh';
use Cpanel::JSON              ();
use Cpanel::TaskQueue::Reader ();
use Cpanel::Time::ISO         ();
use Cpanel::TimeHiRes         ();

use constant {
    _EINTR => 4,

    _DEBOUNCE_TIME => 0.2,    #seconds

    _HEARTBEAT_TIMEOUT => 30,
};

use constant TASK_ACCESSORS_TO_COPY => (
    'timestamp',
    'pid',
);

=head1 METHODS

These aren’t really meant to be called except by
L<Cpanel::Server::Handlers::SSE>.

=head2 I<CLASS>->new(...)

See L<Cpanel::Server::SSE> for the arguments that this takes.

=cut

sub new {
    my ( $class, @opts_kv ) = @_;

    my $self = $class->SUPER::new(@opts_kv);

    $self->{'files'} = {
        queue => $Cpanel::TaskQueue::Reader::QUEUE_FILE,
        sched => $Cpanel::TaskQueue::Reader::SCHED_FILE,
    };

    for my $watched ( keys %{ $self->{'files'} } ) {
        $self->{"i_$watched"} = Cpanel::Inotify->new( flags => ['NONBLOCK'] );
        $self->{"i_$watched"}->add(
            $self->{'files'}{$watched},
            flags => [ 'ATTRIB', 'MODIFY' ],
        );

        my $mask = q<>;
        vec( $mask, $self->{"i_$watched"}->fileno(), 1 ) = 1;

        $self->{"mask_$watched"} = $mask;
    }

    return $self;
}

=head2 I<OBJ>->run(...)

Does the main work of this module. It runs an infinite loop, so the only
way that this ends is via an exception (e.g., from an I/O error) or via
a signal.

=cut

sub run {
    my ($self) = @_;

    for my $watched ( keys %{ $self->{'files'} } ) {
        my $fname = "_send_$watched";
        $self->$fname($_);
    }

    my $rmask = $self->{"mask_queue"} | $self->{"mask_sched"};

    #This task probably should not time out because this is a monitoring
    #process, not a request/response. However, we don’t want the process
    #to continue indefinitely, so let’s just say a 1-week timeout is
    #close enough to “lasts forever”.
    alarm( 86400 * 7 );

    #It would be ideal to have some way to know that the client is gone
    #so we could shut down right away; however, we don’t have that because
    #TCP doesn’t give us a way to know that the peer has stopped reading.
    while (1) {
        my $res = select( my $rout = $rmask, undef, undef, $self->_HEARTBEAT_TIMEOUT() );

        if ( $res > 0 ) {
            my $now = Cpanel::TimeHiRes::time();

            for my $watched ( keys %{ $self->{'files'} } ) {
                if ( ( $rout & $self->{"mask_$watched"} ) eq $self->{"mask_$watched"} ) {

                    $self->{'_send_time'}{$watched} = $now + _DEBOUNCE_TIME();

                    #Clear out the inotify handle. It doesn’t matter
                    #what the event is; we just need to consume it.
                    () = $self->{"i_$watched"}->poll();
                }
            }

            $self->_debounce();
        }
        elsif ( $res == 0 ) {
            $self->_send_sse_heartbeat();
        }
        else {
            die "select(): $!" if $! != _EINTR();
        }
    }

    return;
}

sub _debounce {
    my ( $self, $rmask ) = @_;

  LOOP_CHECK:
    while ( %{ $self->{'_send_time'} } ) {
        my $now = Cpanel::TimeHiRes::time();

        for my $watched ( keys %{ $self->{'_send_time'} } ) {
            if ( $now >= $self->{'_send_time'}{$watched} ) {

                #It’s now past the appointed time to send the file.

                delete $self->{'_send_time'}{$watched};

                my $funcname = "_send_$watched";
                $self->$funcname($watched);

                #It may take a bit to read that file, so let’s recheck
                #the time to see if there’s another send-time arrival.
                next LOOP_CHECK;
            }
        }

        #We got here so there is at least one pending send-time.

        my ($next_send_time) = sort { $a <=> $b } values %{ $self->{'_send_time'} };
        die 'no next send time?!?' if !$next_send_time;

        my $time_left = $next_send_time - $now;
        die 'nonpositive time left?!?' if $time_left <= 0;

        my $num = select( my $rout = $rmask, undef, undef, $time_left );

        if ( $num > 0 ) {
            my $now = Cpanel::TimeHiRes::time();

            for my $watched ( keys %{ $self->{'files'} } ) {
                if ( ( $rout & $self->{"mask_$watched"} ) eq $self->{"mask_$watched"} ) {

                    #We got input on the inotify handle. If we don’t
                    #already have a send-time for $watched, let’s
                    #create one. If we do already have such a send-time,
                    #then we just ignore this inotify input.
                    $self->{'_send_time'}{$watched} ||= $now + _DEBOUNCE_TIME();

                    #Clear out the inotify handle. It doesn’t matter
                    #what the event is; we just need to consume it.
                    () = $self->{"i_$watched"}->poll();
                }
            }
        }
        elsif ( $num == -1 ) {
            die "select(): $!" if $! != _EINTR();
        }
    }

    return;
}

use constant _QUEUE_LISTS => ( 'processing', 'waiting', 'deferred' );

sub _send_queue {
    my ($self) = @_;

    my $queue_hr = Cpanel::TaskQueue::Reader::read_queue();

    @{$queue_hr}{ _QUEUE_LISTS() } = delete @{$queue_hr}{
        'processing_queue',
        'waiting_queue',
        'deferral_queue',
    };

    for my $list ( @{$queue_hr}{ _QUEUE_LISTS() } ) {
        $_ = _task_to_hash($_) for @$list;
    }

    return $self->_send_raw( 'queue', $queue_hr );
}

sub _send_sched {
    my ($self) = @_;

    my $sched_ar = Cpanel::TaskQueue::Reader::read_sched()->{'waiting_queue'};
    $_->{'task'} = _task_to_hash( $_->{'task'} ) for @$sched_ar;

    return $self->_send_raw( 'sched', $sched_ar );
}

sub _task_to_hash {
    my ($task) = @_;

    my $timeout = $task->{'_child_timeout'};

    return {
        command           => [ $task->{'_command'}, @{ $task->{'_args'} } ],
        child_timeout     => ( $timeout == -1 ) ? undef : $timeout,
        id                => $task->{'_uuid'},
        retries_remaining => $task->{'_retries'},
        map { ( $_ => $task->{"_$_"} ) } TASK_ACCESSORS_TO_COPY(),
    };
}

sub _send_raw {
    my ( $self, $watched, $payload ) = @_;

    my $id = join(
        '/',
        $watched,
        Cpanel::Time::ISO::unix2iso(),
        sprintf( '%x', substr( rand, 2 ) ),
    );

    $self->_send_sse_message(
        id    => $id,
        event => "$watched-update",
        data  => Cpanel::JSON::Dump($payload),
    );

    return;
}

1;
