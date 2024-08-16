package Cpanel::Dovecot::FTSRescanQueue::Harvester;

# cpanel - Cpanel/Dovecot/FTSRescanQueue/Harvester.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::FTSRescanQueue::Harvester

=head1 SYNOPSIS

    my $mailboxes_ar = Cpanel::Dovecot::FTSRescanQueue::Harvester->harvest();

=head1 DESCRIPTION

The fts_rescan_mailbox cache queue’s “harvester” module. See
L<Cpanel::Dovecot::FTSRescanQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Dovecot::FTSRescanQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
