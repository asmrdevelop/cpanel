package Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Adder;

# cpanel - Cpanel/Dovecot/FlushcPanelAccountAuthQueue/Adder.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Adder

=head1 SYNOPSIS

    Cpanel::Dovecot::FlushcPanelAccountAuthQueue::Adder->add($mailbox);

=head1 DESCRIPTION

The flush_cpanel_account_dovecot_auth_cache_queue queue’s “adder” module. See
L<Cpanel::Dovecot::FlushcPanelAccountAuthQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Dovecot::FlushcPanelAccountAuthQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
