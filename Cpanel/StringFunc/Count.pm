package Cpanel::StringFunc::Count;

# cpanel - Cpanel/StringFunc/Count.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::StringFunc::Count - Functions for counting strings within strings

=head1 SYNOPSIS

    use Cpanel::StringFunc::Count ();

    my $number_of_dots = Cpanel::StringFunc::Count::countchar('dog.f.cow.pig','.'); # 3
    my $curly_brace_count = Cpanel::StringFunc::Count::get_curly_brace_count('include {}); # 1

=cut

################################################################################
# countchar -- New version can count any blocks ie
#
# countchar('aXXXXb','X'); = 4
# countchar('aXXXXb','Xb'); = 1
################################################################################

=head2 countchar( $string, $match )

Counts the occurrence of a string (not necessarily char).

=over 2

=item Input

=over 4

=item I<scalar> (string)

Input string to look through

=item I<scalar> (string)

Input string or regex to match off of

=back

=item Output

Numeric count of matching occurrences found.

=back

=cut

sub countchar {
    return 0 unless length $_[0] && length $_[1];
    my $count = 0;
    $count++ while $_[0] =~ /\Q$_[1]\E/g;
    return $count;
}

# Since we are only using single chars tr// is about 1272% faster then using the same logic as countchar

=head2 get_curly_brace_count( $string )

Counts the number of unmatched curly braces

=over 2

=item Input

=over 4

=item I<scalar> (string)

String with 0 or more curly braces.

=back

=item Output

If there's no curly braces, returns 0.  If there's an equal number of { and }
braces, returns 0.  If there's more {, then returns a value > 0.  If there's
more }, then returns a value < 0.

IMPORTANT NOTE: Does not care if the braces match.

=back

=cut

sub get_curly_brace_count {
    return 0 unless $_[0];
    return ( ( $_[0] =~ tr/{// ) - ( $_[0] =~ tr/}// ) );
}

=head1 BUGS AND LIMITATIONS

=over 2

=item countchar() does not return correct results when supplying an undef character match string.

=item countchar() does not return correct results when supplying a non-string value as the first parameter.

=back

=cut

1;
