package Cpanel::FtpUtils::UpdateQueue::Adder;

# cpanel - Cpanel/FtpUtils/UpdateQueue/Adder.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FtpUtils::UpdateQueue::Adder

=head1 SYNOPSIS

    Cpanel::FtpUtils::UpdateQueue::Adder->add($ftpupdate_args);

=head1 DESCRIPTION

The ftpupdate queue’s “adder” module. See
L<Cpanel::FtpUtils::UpdateQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::FtpUtils::UpdateQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
