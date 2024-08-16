package Cpanel::TaskProcessors::NotificationTasks::Harvester;

# cpanel - Cpanel/TaskProcessors/NotificationTasks/Harvester.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::NotificationTasks::Harvester

=head1 SYNOPSIS

    Cpanel::TaskProcessors::NotificationTasks::Harvester->Harvester( sub {
        my (@notify_args) = @_;

        ...;
    } );

=head1 DISCUSSION

This is the harvester module for the NotificationTasks subqueue.

=cut

use parent qw(
  Cpanel::TaskProcessors::NotificationTasks::SubQueueBase
  Cpanel::TaskQueue::SubQueue::Harvester
);

=head1 METHODS

=head2 I<CLASS>->harvest( CALLBACK )

Similar to the base class’s method of the same name, but with some
differences:

=over

=item * The CALLBACK is required.

=item * The CALLBACK receives an individual entry’s arguments as a list.
These are the same arguments passed to the adder module’s C<add()> function.

=back

It is by design that the queue item names are not exposed.

=cut

sub harvest {
    my ( $class, $foreach_cr ) = @_;

    die 'Must have a callback!' if !$foreach_cr;

    $class->SUPER::harvest(
        sub {
            my ( undef, $payload_ar ) = @_;

            return $foreach_cr->(@$payload_ar);
        }
    );

    return;
}

1;
