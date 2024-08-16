package Cpanel::DNSSEC::VerifyQueue::Adder;

# cpanel - Cpanel/DNSSEC/VerifyQueue/Adder.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DNSSEC::VerifyQueue::Adder

=head1 SYNOPSIS

    Cpanel::DNSSEC::VerifyQueue::Adder->add($zone);

=head1 DESCRIPTION

The verify_dnssec_sync queue’s “adder” module. See
L<Cpanel::DNSSEC::VerifyQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::DNSSEC::VerifyQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
