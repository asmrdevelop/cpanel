package Cpanel::Config::userdata::CacheQueue::Harvester;

# cpanel - Cpanel/Config/userdata/CacheQueue/Harvester.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::userdata::CacheQueue::Harvester

=head1 SYNOPSIS

    my $usernames_ar = Cpanel::Config::userdata::CacheQueue::Harvester->harvest();

=head1 DESCRIPTION

The userdata cache queue’s “harvester” module. See
L<Cpanel::Config::userdata::CacheQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Config::userdata::CacheQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
