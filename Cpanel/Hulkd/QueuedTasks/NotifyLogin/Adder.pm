package Cpanel::Hulkd::QueuedTasks::NotifyLogin::Adder;

# cpanel - Cpanel/Hulkd/QueuedTasks/NotifyLogin/Adder.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::QueuedTasks::NotifyLogin::Adder

=head1 SYNOPSIS

    Cpanel::Hulkd::QueuedTasks::NotifyLogin::Adder->add($json_string);

=head1 DESCRIPTION

The NotifyLogin subqueue “adder” module. See
L<Cpanel::Hulkd::QueuedTasks::NotifyLogin> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Hulkd::QueuedTasks::NotifyLogin
  Cpanel::Hulkd::QueuedTasks::Adder
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
