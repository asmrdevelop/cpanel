package Cpanel::FtpUtils::UpdateQueue::Harvester;

# cpanel - Cpanel/FtpUtils/UpdateQueue/Harvester.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FtpUtils::UpdateQueue::Harvester

=head1 SYNOPSIS

    my $ftpupdates_ar = Cpanel::FtpUtils::UpdateQueue::Harvester->harvest();

=head1 DESCRIPTION

The ftpupdate cache queue’s “harvester” module. See
L<Cpanel::FtpUtils::UpdateQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::FtpUtils::UpdateQueue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
