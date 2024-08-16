package Cpanel::TaskProcessors::NotificationTasks::SubQueueBase;

# cpanel - Cpanel/TaskProcessors/NotificationTasks/SubQueueBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskProcessors::NotificationTasks::SubQueueBase

=head1 SYNOPSIS

n/a

=head1 DESCRIPTION

This is a base class for the NotificationTasks subqueue.
This subqueue stores notification tasks. The notifications are stored
and harvested in chronological order.

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

#overwritten in tests
our $_DIR = '/var/cpanel/taskqueue/groups/NotificationTasks';

sub _DIR {
    return $_DIR;
}

1;
