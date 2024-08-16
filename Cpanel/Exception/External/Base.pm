package Cpanel::Exception::External::Base;

# cpanel - Cpanel/Exception/External/Base.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Exception::External::Base - base class for external exceptions

=head1 DESCRIPTION

This base class adds no additional functionality over C<Cpanel::Exception>,
but C<Cpanel::Exception::External> looks for this to determine whether a given
exception module is meant for external consumption.

Only cPanel developers should load this module directly.

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Exception
);

1;
