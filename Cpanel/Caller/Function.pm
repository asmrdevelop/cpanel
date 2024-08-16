package Cpanel::Caller::Function;

# cpanel - Cpanel/Caller/Function.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Caller::Function

=head1 SYNOPSIS

    my $last_public_caller = Cpanel::Caller::Function::get_latest_public();

=head1 DESCRIPTION

This module contains logic to analyze the call stack for different functions.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 get_latest_public()

Returns the name (without namespace) of the latest-called public
function in the call stack.

If there is no public-named function in the call stack, this throws an
exception.

=cut

sub get_latest_public() {
    my $lv = 1;

    while ( my $fn = ( caller $lv )[3] ) {
        $fn =~ s<.+::><>;

        return $fn if 0 != rindex( $fn, '_', 0 );

        $lv++;
    }

    die "Found no public function in the call stack ($lv levels)!";
}

1;
