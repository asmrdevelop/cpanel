package Cpanel::Hash::Stringify;

# cpanel - Cpanel/Hash/Stringify.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Hash::Stringify - Convert a hash into a string that can be used to compare

=head1 SYNOPSIS

    use Cpanel::Hash::Stringify;

    my $string = Cpanel::Hash::Stringify::sorted_hashref_string($hashref);

=head1 WHEN DO USE THIS MODULE

This module is for low memory footprint use cases.  If you have Cpanel::JSON
available, Cpanel::JSON::canonical_dump is likely a better choice.

=head1 FUNCTIONS

=head2 sorted_hashref_string($hashref)

Returns a string that reproducibly represents the hash that can be used to
represent or compare the contents of the hash

=cut

sub sorted_hashref_string {
    my ($hashref) = @_;
    return (
        ( scalar keys %$hashref )
        ? join(
            '_____', map { $_, ( ref $hashref->{$_} eq 'HASH' ? sorted_hashref_string( $hashref->{$_} ) : ref $hashref->{$_} eq 'ARRAY' ? join( '_____', @{ $hashref->{$_} } ) : defined $hashref->{$_} ? $hashref->{$_} : '' ) }
              sort keys %$hashref
          )
        : ''
    );    #sort is important for order;
}

1;
