package Cpanel::PHPFPM::RebuildQueue::Harvester;

# cpanel - Cpanel/PHPFPM/RebuildQueue/Harvester.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PHPFPM::RebuildQueue::Harvester

=head1 SYNOPSIS

    my $usernames_ar = Cpanel::PHPFPM::RebuildQueue::Harvester->harvest();

=head1 DESCRIPTION

The Rebuild queue’s “harvester” module.

=cut

use parent qw(
  Cpanel::PHPFPM::RebuildQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
