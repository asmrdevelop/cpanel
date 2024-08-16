package Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Harvester;

# cpanel - Cpanel/Dovecot/FlushcPanelAccountAuthQueue/Harvester.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Harvester

=head1 SYNOPSIS

    my $mailboxes_ar = Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Harvester->harvest();

=head1 DESCRIPTION

The flush_cpanel_account_dovecot_auth_cache_queue cache queue’s “harvester” module. See
L<Cpanel::Dovecot::FlushcPanelAccountAuthQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Dovecot::FlushcPanelAccountAuthQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
