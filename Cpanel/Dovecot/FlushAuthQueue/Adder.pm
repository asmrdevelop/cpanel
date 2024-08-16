package Cpanel::Dovecot::FlushAuthQueue::Adder;

# cpanel - Cpanel/Dovecot/FlushAuthQueue/Adder.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::FlushAuthQueue::Adder

=head1 SYNOPSIS

    Cpanel::Dovecot::FlushAuthQueue::Adder->add($mailbox);

=head1 DESCRIPTION

The fts_rescan_mailbox queue’s “adder” module. See
L<Cpanel::Dovecot::FlushAuthQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Dovecot::FlushAuthQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
