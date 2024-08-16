package Cpanel::FileProtect::Queue::Harvester;

# cpanel - Cpanel/Config/userdata/CacheQueue/Harvester.pm
#                                                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FileProtect::Queue::Harvester

=head1 SYNOPSIS

    my $users_ar = Cpanel::FileProtect::Queue::Harvester->harvest();

=head1 DESCRIPTION

The fileprotect queue’s “harvester” module. See
L<Cpanel::FileProtect::Queue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::FileProtect::Queue
  Cpanel::TaskQueue::SubQueue::Harvester
);

1;
