package Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser;

# cpanel - Cpanel/Hulkd/QueuedTasks/AddKnownIPForUser.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser

=head1 SYNOPSIS

(See subclasses.)

=head1 DESCRIPTION

This subqueue exists to alleviate issues concerning the size of the
single file queue used in C<Cpanel::TaskQueue>.

It allows us to write events into individual files in the 'subqueue'
directory, instead of having a single file contain all the data for
the events.

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

sub _DIR {
    return '/var/cpanel/taskqueue/groups/cphulk_add_known_ip_for_user';
}

sub todo_dir {
    return $_[0]->_DIR() . '/.todo';
}

1;
