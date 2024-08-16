package Cpanel::Hulkd::QueuedTasks::BlockBruteForce::Adder;

# cpanel - Cpanel/Hulkd/QueuedTasks/BlockBruteForce/Adder.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::QueuedTasks::BlockBruteForce::Adder

=head1 SYNOPSIS

    Cpanel::Hulkd::QueuedTasks::BlockBruteForce::Adder->add($json_string);

=head1 DESCRIPTION

The BlockBruteForce subqueue “adder” module. See
L<Cpanel::Hulkd::QueuedTasks::BlockBruteForce> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Hulkd::QueuedTasks::BlockBruteForce
  Cpanel::Hulkd::QueuedTasks::Adder
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
