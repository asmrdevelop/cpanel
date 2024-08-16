package Cpanel::Set;

# cpanel - Cpanel/Set.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Set - set operations

=head1 SYNOPSIS

    my @diff = Cpanel::Set::difference( \@super, \@sub );

    my @ntersec = Cpanel::Set::intersection( \@super, \@sub );

=head1 DISCUSSION

L<Set::Scalar> can provide more comprehensive coverage of set operations;
this module is here as a lighter, simpler alternative.

=head1 FUNCTIONS

=cut

=head2 difference( \@a, \@b [, \@c, \@d, ...] )

Gives a list of all elements in C<@a> that are not in C<@b>
(nor any other successive list).
C<@a>’s order is preserved.

If called in scalar context, returns the number of items that
would be returned in list context.

=cut

sub difference {
    my ($super_ar) = @_;

    my %lookup;
    @lookup{ map { @$_ } @_[ 1 .. $#_ ] } = ();

    return grep { !exists $lookup{$_} } @$super_ar;
}

=head2 intersection( \@a, \@b )

Gives a list of all elements in C<@a> that are in C<@b>.
C<@a>’s order is preserved.

If called in scalar context, returns the number of items that
would be returned in list context.

=cut

sub intersection {
    my ( $super_ar, $sub_ar ) = @_;

    my %lookup;
    @lookup{@$sub_ar} = ();

    return grep { exists $lookup{$_} } @$super_ar;
}

1;
