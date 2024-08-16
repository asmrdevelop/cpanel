package Cpanel::PHPFPM::EnableQueue::Harvester;

# cpanel - Cpanel/PHPFPM/EnableQueue/Harvester.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PHPFPM::EnableQueue::Harvester

=head1 SYNOPSIS

    my $usernames_ar = Cpanel::PHPFPM::EnableQueue::Harvester->harvest();

=head1 DESCRIPTION

The Enable queue’s “harvester” module.

=cut

use parent qw(
  Cpanel::PHPFPM::EnableQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
