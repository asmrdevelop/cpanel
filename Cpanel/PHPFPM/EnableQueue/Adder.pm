package Cpanel::PHPFPM::EnableQueue::Adder;

# cpanel - Cpanel/PHPFPM/EnableQueue/Adder.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::PHPFPM::EnableQueue::Adder

=head1 SYNOPSIS

    Cpanel::PHPFPM::EnableQueue::Adder->add($domain);

=head1 DESCRIPTION

The enable queue’s “adder” module.

=cut

use parent qw(
  Cpanel::PHPFPM::EnableQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
