package Cpanel::Config::userdata::CacheQueue::Adder;

# cpanel - Cpanel/Config/userdata/CacheQueue/Adder.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Config::userdata::CacheQueue::Adder

=head1 SYNOPSIS

    Cpanel::Config::userdata::CacheQueue::Adder->add($username);

=head1 DESCRIPTION

The userdata cache queue’s “adder” module. See
L<Cpanel::Config::userdata::CacheQueue> for general documentation
about this queue.

=cut

use parent qw(
  Cpanel::Config::userdata::CacheQueue
  Cpanel::TaskQueue::SubQueue::Adder
);

use Cpanel::Validate::Username ();

=head1 METHODS

=head2 I<CLASS>->add( USERNAME )

Validates the USERNAME and adds it to the queue.

=cut

sub add {
    my ( $class, $name ) = @_;

    Cpanel::Validate::Username::validate_or_die($name);

    return $class->SUPER::add($name);
}

1;
