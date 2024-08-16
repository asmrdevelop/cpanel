package Cpanel::DNSSEC::VerifyQueue;

# cpanel - Cpanel/DNSSEC/VerifyQueue.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DNSSEC::VerifyQueue;

=head1 SYNOPSIS

(See subclasses.)

=head1 DESCRIPTION

This subqueue exists because of the following scenario:

=over

=item 1) Task queue has C<verify_dnssec_sync zone>

=item 2) We enqueue C<verify_dnssec_sync zone>

=back

At this point we want task #1 to incorporate C<zone> rather than
having two nearly-identical tasks in the task queue. L<Cpanel::TaskQueue>
doesn’t facilitate that very readily, though, so instead we store zones
in this harvester queue (i.e., the present module and subclasses) and have
C<verify_dnssec_sync> harvest from the queue rather than taking arguments.

This module, then, is a “sub-queue” of sorts for the server’s main cPanel
task queue.

This also reduces the number of items in the queue to prevent overloading
taskqueue

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

our $_DIR = '/var/cpanel/taskqueue/groups/verify_dnssec_sync';

sub _DIR { return $_DIR; }

1;
