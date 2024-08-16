package Cpanel::Dovecot::FTSRescanQueue::Adder;

# cpanel - Cpanel/Dovecot/FTSRescanQueue/Adder.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::FTSRescanQueue::Adder

=head1 SYNOPSIS

    Cpanel::Dovecot::FTSRescanQueue::Adder->add($mailbox);

=head1 DESCRIPTION

The fts_rescan_mailbox queue’s “adder” module. See
L<Cpanel::Dovecot::FTSRescanQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Dovecot::FTSRescanQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
