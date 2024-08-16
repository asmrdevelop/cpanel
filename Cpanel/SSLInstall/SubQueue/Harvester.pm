package Cpanel::SSLInstall::SubQueue::Harvester;

# cpanel - Cpanel/SSLInstall/SubQueue/Harvester.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSLInstall::SubQueue::Harvester

=head1 DESCRIPTION

This module subclasses L<Cpanel::TaskQueue::SubQueue::Harvester> to make
a concrete interface.

=cut

use parent qw(
  Cpanel::SSLInstall::SubQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
