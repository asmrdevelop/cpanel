package Cpanel::DnsUtils::RNDCQueue;

# cpanel - Cpanel/DnsUtils/RNDCQueue.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::RNDCQueue

=head1 SYNOPSIS

(See subclasses.)

=head1 DESCRIPTION

The Reload Sub Queue is designed to queue a list of zones
that we want to reload

=cut

use parent qw( Cpanel::TaskQueue::SubQueue );

our $_DIR = '/var/cpanel/taskqueue/groups/rndc_subqueue';

sub _DIR () { return $_DIR; }

1;
