package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/print.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 FUNCTIONS

=head2 print( .. )

cf. L<perlfunc/print>

A bit more restrictive than Perl’s built-in: in particular,
a file handle is still optional, but it MUST be a reference.

This does still fall back to C<$_> and does still use the default file handle
if either the LIST or FILEHANDLE is omitted.

=cut

sub print {    ## no critic(RequireArgUnpacking)
    my $args_ar = \@_;

    local ( $!, $^E );

    my $ret;

    if ( UNIVERSAL::isa( $args_ar->[0], 'GLOB' ) ) {
        $ret = CORE::print { shift @$args_ar } ( @$args_ar ? @$args_ar : $_ );
    }
    else {
        $ret = CORE::print( @$args_ar ? @$args_ar : $_ );
    }

    if ($!) {

        #Figure out the "length" to report to the exception object.
        my $length;
        if (@$args_ar) {
            $length = 0;
            $length += length for @$args_ar;
        }
        else {
            $length = length;
        }

        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::WriteError', [ length => $length, error => $err ] );
    }

    return $ret;
}

1;
