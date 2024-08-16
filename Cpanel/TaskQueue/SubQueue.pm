package Cpanel::TaskQueue::SubQueue;

# cpanel - Cpanel/TaskQueue/SubQueue.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::TaskQueue::SubQueue

=head1 SYNOPSIS

(See subclasses.)

=head1 DESCRIPTION

This is a base class for handlers for Cpanel::TaskQueue “subqueues”.

These datastores aren’t really proper “queues” because they aren’t
ordered, but “subqueue” has seemed a sensible term.

This datastore is useful to prevent lots of processes that could all
be handled together. TaskQueue’s C<overrides()> and C<is_dupe()> methods
don’t work very well for this because we need the “overriding” task to
B<replace> the “overridden” task in order to maintain execution order
in the queue. TaskQueue also seems to expect that a given task, once
enqueued, will not change. TaskQueue has been in production for a good
while now, and it seems best to address these concerns without altering
fairly deep-down, “assumption-y” behavior like this.

=head1 SUBCLASS INTERFACE

B<IMPORTANT:> You need to provide a C<_DIR()> method for this to work.

=cut

use constant _CONTENT_PREFIX => '.content.';

sub _DIR { die 'ABSTRACT' }

1;
