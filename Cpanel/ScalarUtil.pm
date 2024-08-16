package Cpanel::ScalarUtil;

# cpanel - Cpanel/ScalarUtil.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ScalarUtil

=head1 SYNOPSIS

    my $blessed = Cpanel::ScalarUtil::blessed($whatsit);

=head1 DESCRIPTION

This module implements a subset of L<Scalar::Util>’s functionality in pure
Perl.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

The following match L<Scalar::Util> implementations exactly:

=over

=item * C<blessed()>

=back

=cut

sub blessed {
    return ref( $_[0] ) && UNIVERSAL::isa( $_[0], 'UNIVERSAL' ) || undef;
}

1;
