package Cpanel::FHUtils::Tiny;

# cpanel - Cpanel/FHUtils/Tiny.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FHUtils::Tiny - A few “tiny” utilities for using filehandles.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_a( $SPECIMEN )

Returns a boolean that indicates whether $SPECIMEN is a Perl filehandle.
(This may not work in all cases but is fine for general use.)

=cut

sub is_a {
    return !ref $_[0] ? 0 : ( ref $_[0] eq 'IO::Handle' || ref $_[0] eq 'GLOB' || UNIVERSAL::isa( $_[0], 'GLOB' ) ) ? 1 : 0;
}

=head2 $yn = are_same( $FH1, $FH2 )

Returns a boolean that indicates whether $FH1 and $FH2 are the same
underlying file descriptor.

=cut

sub are_same {
    my ( $fh1, $fh2 ) = @_;

    #optimization
    return 1 if $fh1 eq $fh2;

    if ( fileno($fh1) && ( fileno($fh1) != -1 ) && fileno($fh2) && ( fileno($fh2) != -1 ) ) {
        return 1 if fileno($fh1) == fileno($fh2);
    }

    return 0;
}

=head2 $mask = to_bitmask( @FHS_OR_FDS )

Returns a bitmask that combines the passed-in filehandles or file
descriptors. The returned bitmask is suitable for use in C<select()>.

=cut

#Creates a bitmask out of one or more file handles.
#Such a bitmask is suitable for use in select().
sub to_bitmask {
    my @fhs = @_;

    my $mask = q<>;

    for my $fh (@fhs) {
        vec( $mask, ref($fh) ? fileno($fh) : $fh, 1 ) = 1;
    }

    return $mask;
}

1;
