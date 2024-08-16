package Cpanel::Sort::Multi;

# cpanel - Cpanel/Sort/Multi.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Sort::Multi

=head1 SYNOPSIS

    my @sorts = do {
        package Cpanel::Sort::Multi;
        (
            #Prioritize fewest dots first
            sub { ($a =~ tr<.><>) <=> ($b =~ tr<.><>) },

            #Then prioritize shortest text
            sub { length($a) <=> length($b) },
        );
    };

    my @sorted = Cpanel::Sort::Multi::apply( \@sorts, @unsorted );

=head1 WHY THE UGLY SYNTAX?

Because the globals C<$a> and C<$b> in the subroutines have to
refer to C<$Cpanel::Sort::Multi::a> and C<$Cpanel::Sort::Multi::b>,
respectively, in order for the sorting to work.

Alternatively to the C<package> statement, you can
achieve the same effect by namespacing those variables in the subroutines
manually, e.g.:

    my @sorts = (
        #Prioritize fewest dots first
        sub { ($Cpanel::Sort::Multi::a =~ tr<.><>) <=> ($Cpanel::Sort::Multi::b =~ tr<.><>) },

        #Then prioritize shortest text
        sub { length($Cpanel::Sort::Multi::a) <=> length($Cpanel::Sort::Multi::b) },
    );

… but that seems even uglier.

=cut

use Cpanel::Context ();

our ( $a, $b );

sub apply {
    my ( $sorters_ar, @items ) = @_;

    Cpanel::Context::must_be_list();

    for my $cr ( reverse @$sorters_ar ) {
        @items = sort $cr @items;
    }

    return @items;
}

1;
