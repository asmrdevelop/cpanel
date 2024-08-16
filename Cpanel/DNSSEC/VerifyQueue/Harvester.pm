package Cpanel::DNSSEC::VerifyQueue::Harvester;

# cpanel - Cpanel/DNSSEC/VerifyQueue/Harvester.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DNSSEC::VerifyQueue::Harvester

=head1 SYNOPSIS

    my $mailboxes_ar = Cpanel::DNSSEC::VerifyQueue::Harvester->harvest();

=head1 DESCRIPTION

The verify_dnssec_sync queue’s “harvester” module. See
L<Cpanel::DNSSEC::VerifyQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::DNSSEC::VerifyQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
