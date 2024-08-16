package Cpanel::Hulkd::QueuedTasks::NotifyLogin;

# cpanel - Cpanel/Hulkd/QueuedTasks/NotifyLogin.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::QueuedTasks::NotifyLogin

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
    return '/var/cpanel/taskqueue/groups/cphulk_notify_login';
}

=head1 METHODS

=head2 I<CLASS>->todo_dir()

Returns the directory path which holds the waiting to be processed
jobs.

The jobs are timestamp'ed symlinks to the actual job file that reside
in the C<_DIR()>

=cut

sub todo_dir {
    return $_[0]->_DIR() . '/.todo';
}

1;
