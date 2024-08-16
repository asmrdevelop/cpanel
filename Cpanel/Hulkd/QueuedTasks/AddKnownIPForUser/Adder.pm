package Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser::Adder;

# cpanel - Cpanel/Hulkd/QueuedTasks/AddKnownIPForUser/Adder.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser::Adder

=head1 SYNOPSIS

    Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser::Adder->add($json_string);

=head1 DESCRIPTION

The AddKnownIPForUser subqueue “adder” module. See
L<Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Hulkd::QueuedTasks::AddKnownIPForUser
  Cpanel::Hulkd::QueuedTasks::Adder
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
