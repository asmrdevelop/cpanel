package Cpanel::LinkedNode::QuotaBalancer::Cron;

# cpanel - Cpanel/LinkedNode/QuotaBalancer/Cron.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::QuotaBalancer::Cron - Logic to manage cron jobs for balancing user quotas on linked nodes

=head1 DESCRIPTION

This module handles root’s cron entry to make auto-balancing of user quotas across linked nodes work either
ensuring that it does exist or ensuring that it doesn’t exist.

This module is a concrete implementation of C<Cpanel::Crontab::Entry::Base>. See that module for
implementation details.

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Crontab::Entry::Base
);

use Cpanel::ConfigFiles     ();
use Cpanel::Update::Crontab ();

#referenced from tests
our $COMMAND = "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/balance_linked_node_quotas";

our $CRON_FILE = '/etc/cron.d/cpanel_balance_linked_node_quotas';

# Frequency specified as a number of hours
our $FREQUENCY = 4;

sub _COMMAND {
    return $COMMAND;
}

sub _CRON_FILE {
    return $CRON_FILE;
}

sub _get_crontab_hour_minute_opts {

    my $hour   = "*/$FREQUENCY";
    my $minute = Cpanel::Update::Crontab::get_random_min();

    return ( -minute => $minute, -hour => $hour );
}
1;
