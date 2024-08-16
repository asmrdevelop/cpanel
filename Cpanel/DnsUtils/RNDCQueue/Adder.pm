package Cpanel::DnsUtils::RNDCQueue::Adder;

# cpanel - Cpanel/DnsUtils/RNDCQueue/Adder.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::RNDCQueue::Adder

=head1 SYNOPSIS

 Cpanel::DnsUtils::RNDCQueue::Adder->add("reload");
 Cpanel::DnsUtils::RNDCQueue::Adder->add("reconfig");
 Cpanel::DnsUtils::RNDCQueue::Adder->add("reload $zone");
 Cpanel::DnsUtils::RNDCQueue::Adder->add("reload $zone IN external");
 Cpanel::DnsUtils::RNDCQueue::Adder->add("reload $zone IN internal");

=head1 DESCRIPTION

The RNDCQueue’s “adder” module.

=cut

use parent qw(
  Cpanel::DnsUtils::RNDCQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
