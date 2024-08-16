package Cpanel::IPv6::Sort;

# cpanel - Cpanel/IPv6/Sort.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::IPv6::Sort

=head1 SYNOPSIS

    my @addrs = (
        '2a03:2880:f112:83:face:b00c:0:25de'
        '1::2',
    );

    Cpanel::IPv6::Sort::in_place(\@addrs);

    # @addrs is now sorted.

=head1 DESCRIPTION

Just as it sounds: sort logic for IPv6 addresses.

=head1 SEE ALSO

L<Cpanel::Sort::Utils> and L<Cpanel::Args::Sort::Utils> both contain
IPv4 sorting implementations.

=cut

#----------------------------------------------------------------------

use Cpanel::IP::Expand ();

our ( $a, $b );

#----------------------------------------------------------------------

=head1 METHODS

=head2 $addrs_ar = in_place( \@ADDRESSES )

Sorts @ADDRESSES in-place.

As a convenience, the given reference is returned.

=cut

sub in_place ($addrs_ar) {

    # We have to normalize the addresses first. But we don’t want to
    # alter the actual entries in @$addrs_ar, so we compute the normalized
    # strings and store them in a hash. (This is a less “messy” variant
    # of the “Orcish maneuver”.)

    my %normalized;
    $normalized{$_} //= Cpanel::IP::Expand::expand_ip( $_, 6 ) for @$addrs_ar;

    my @sorted = sort { $normalized{$a} cmp $normalized{$b} } @$addrs_ar;

    @$addrs_ar = @sorted;

    return $addrs_ar;
}

1;
