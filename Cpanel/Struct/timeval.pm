package Cpanel::Struct::timeval;

# cpanel - Cpanel/Struct/timeval.pm                 Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Struct::timeval

=head1 SYNOPSIS

    my $float = Cpanel::Struct::timeval->binary_to_float( $binstr );

    my $binstr = Cpanel::Struct::timeval->float_to_binary( $float );

… or, if you just want a reliable, tested C<pack()> template:

    my $binstr = pack(
        Cpanel::Struct::timeval->PACK_TEMPLATE(),
        $secs, $usecs
    );

=head1 DESCRIPTION

This module is an interface to C<struct timeval>.

It exposes the interface documented in L<Cpanel::Struct::Common::Time>,
with microsecond precision.

=cut

use parent 'Cpanel::Struct::Common::Time';

use constant {
    _PRECISION => 1_000_000,    # microseconds
};

1;
