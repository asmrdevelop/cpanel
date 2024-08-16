package Cpanel::ArrayFunc::Shuffle;

# cpanel - Cpanel/ArrayFunc/Shuffle.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ArrayFunc::Shuffle - Pseudo-random shuffles each of the elements in the array reference.

=head2 shuffle( $array_ref )

=over

Pseudo-random shuffles each of the elements in the array reference.

=back

=cut

sub shuffle {
    my $element_to_shuffle = scalar @{ $_[0] };
    my $element_to_exchange;
    while ( $element_to_shuffle-- ) {
        $element_to_exchange = int rand( $element_to_shuffle + 1 );
        @{ $_[0] }[ $element_to_shuffle, $element_to_exchange ] = @{ $_[0] }[ $element_to_exchange, $element_to_shuffle ];
    }
    return $_[0];
}
1;
