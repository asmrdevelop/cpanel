package Cpanel::FileProtect::Queue::Adder;

# cpanel - Cpanel/FileProtect/Queue/Adder.pm
#                                                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FileProtect::Queue::Adder

=head1 SYNOPSIS

    Cpanel::FileProtect::Queue::Adder->add($user);

=head1 DESCRIPTION

The fileprotect queue’s “adder” module. See
L<Cpanel::FileProtect::Queue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::FileProtect::Queue
  Cpanel::TaskQueue::SubQueue::Adder
);

1;
