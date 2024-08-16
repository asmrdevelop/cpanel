package Cpanel::DnsUtils::RNDCQueue::Harvester;

# cpanel - Cpanel/DnsUtils/RNDCQueue/Harvester.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::RNDCQueue::Harvester

=head1 SYNOPSIS

    Cpanel::DnsUtils::RNDCQueue::Harvester->harvest(
      sub {
        my($rndc_args) = @_;

        ....
      }
    );

=head1 DESCRIPTION

The RNDCQueue’s “harvester” module.

=cut

use parent qw(
  Cpanel::DnsUtils::RNDCQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
