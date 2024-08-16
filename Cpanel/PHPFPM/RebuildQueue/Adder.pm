package Cpanel::PHPFPM::RebuildQueue::Adder;

# cpanel - Cpanel/PHPFPM/RebuildQueue/Adder.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PHPFPM::RebuildQueue::Adder

=head1 SYNOPSIS

    Cpanel::PHPFPM::RebuildQueue::Adder->add($domain);

=head1 DESCRIPTION

The enable queue’s “adder” module.

=cut

use parent qw(
  Cpanel::PHPFPM::RebuildQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
