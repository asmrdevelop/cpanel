package Cpanel::Dovecot::FlushAuthQueue::Harvester;

# cpanel - Cpanel/Dovecot/FlushAuthQueue/Harvester.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::FlushAuthQueue::Harvester

=head1 SYNOPSIS

    my $mailboxes_ar = Cpanel::Dovecot::FlushAuthQueue::Harvester->harvest();

=head1 DESCRIPTION

The fts_rescan_mailbox cache queue’s “harvester” module. See
L<Cpanel::Dovecot::FlushAuthQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Dovecot::FlushAuthQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
