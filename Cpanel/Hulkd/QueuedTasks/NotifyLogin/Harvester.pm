package Cpanel::Hulkd::QueuedTasks::NotifyLogin::Harvester;

# cpanel - Cpanel/Hulkd/QueuedTasks/NotifyLogin/Harvester.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::QueuedTasks::NotifyLogin::Harvester

=head1 SYNOPSIS

    my @known_ips_to_add;
    Cpanel::Hulkd::QueuedTasks::NotifyLogin::Harvester->harvest(
        sub { push @known_ips_to_add, shift }
    );
    foreach my $ip (@known_ips_to_add) {
        _do_work($ip);
    }

=head1 DESCRIPTION

The NotifyLogin subqueue “harvester” module. See
L<Cpanel::Hulkd::QueuedTasks::NotifyLogin> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Hulkd::QueuedTasks::NotifyLogin
  Cpanel::Hulkd::QueuedTasks::Harvester
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
