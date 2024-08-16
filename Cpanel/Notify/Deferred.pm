package Cpanel::Notify::Deferred;

# cpanel - Cpanel/Notify/Deferred.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Notify::Deferred - queueprocd-fired notifications

=head1 SYNOPSIS

    Cpanel::Notify::Deferred::notify( @args )

=head1 DESCRIPTION

This module is a thin wrapper that provides a drop-in replacement for
L<Cpanel::Notify>’s in-process notifications.

=cut

use Cpanel::ServerTasks                              ();
use Cpanel::TaskProcessors::NotificationTasks::Adder ();

use constant DEDUPE_TIME => 4;    # ~4 seconds between autossl notify

=head1 FUNCTIONS

=head2 notify( KEY1 => VALUE1, .. )

This interface is a drop-in replacement for
C<Cpanel::Notify::notification_class()>. The difference is that
queueprocd, rather than the current process, will fire the notification.
This can save significantly on server load if it is expected that
a large number of notifications could be sent together.

Nothing is returned; errors are reported via exceptions.

=cut

sub notify {
    notify_without_triggering_subqueue(@_);

    #Have queueprocd do it so that we don’t create kazoodles of
    #notification processes which cripple lower-powered servers.
    process_notify_subqueue();

    return;
}

=head2 process_notify_subqueue

This function will cause all the notifications that were queued
in notify_without_triggering_subqueue to be sent as soon as
queueprocd can process the queue.

This function returns the result from Cpanel::ServerTasks::schedule_task

=cut

sub process_notify_subqueue {
    return Cpanel::ServerTasks::schedule_task(
        ['NotificationTasks'],
        DEDUPE_TIME,
        'notify_from_subqueue',
    );
}

=head2 notify_without_triggering_subqueue( KEY1 => VALUE1, .. )

This function works exactly the same as notify except it does
not trigger processing of the notification subqueue.  It is
most useful when you want to place multiple notifications in
the subqueue and then send them all in a single batch.

*WARNING* You must manually call the notify_from_subqueue task
queue command if you call this function or notifications will
not be sent. (Alternatively, call C<process_notify_subqueue()>,
whose purpose is to do that.)

=cut

sub notify_without_triggering_subqueue {
    my (@notify_args) = @_;

    for ( my $i = 0; $i < scalar @notify_args; $i += 2 ) {
        if ( $notify_args[$i] eq 'constructor_args' ) {
            if ( !grep { length $_ && $_ eq 'block_on_send' } @{ $notify_args[ $i + 1 ] } ) {
                push @{ $notify_args[ $i + 1 ] }, 'block_on_send' => 1;
            }
            last;
        }
    }

    #We don’t want a queueprocd entry for each and every notification.
    return Cpanel::TaskProcessors::NotificationTasks::Adder->add(@notify_args);

}

1;
