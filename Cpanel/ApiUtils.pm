
# cpanel - Cpanel/ApiUtils.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ApiUtils;

use strict;

=head1 NAME

Cpanel::ApiUtils

=head1 FUNCTIONS

=head2 dot_syntax_expand

For APIs that need to accept a representation of structured data despite the limitation to
flat key/value pairs in argument processing, this function allows you to use a simple dot
syntax which will be expanded to the structured format.

Accepts a hash ref and modifies it in place. Returns true if any changes were made and false otherwise.

Example of the transformation:

    Before: { 'name.first' => 'Jane', 'name.last' => 'Doe' }
     After: { name => { first => 'Jane', last => 'Doe' } }

=cut

sub dot_syntax_expand {
    my ($args) = @_;
    my $altered = 0;
    foreach my $k ( _sort_keys($args) ) {
        if ( $k =~ tr/.// ) {
            my $v      = delete $args->{$k};
            my @layers = split /\./, $k;
            my $ptr    = \$args;
            for my $thislayer (@layers) {
                ${$ptr}->{$thislayer} ||= {};
                if ( 'HASH' ne ref ${$ptr}->{$thislayer} ) {
                    die sprintf "While attempting to travel down layer “%s” of “%s”, found an existing non-hash value “%s”.\n", $thislayer, $k, ${$ptr}->{$thislayer};
                }
                $ptr = \${$ptr}->{$thislayer};
            }
            if ( defined $$ptr && !( 'HASH' eq ref $$ptr && !keys %{$$ptr} ) ) {

                # This error is expected to be unreachable because any collisions would have triggered
                # the "While attempting to travel ..." error first due to the alphabetic key sort order.
                die sprintf "While attempting set value at “%s”, found an existing value “%s”.\n", $k, $$ptr;
            }
            $$ptr    = $v;
            $altered = 1;
        }
    }
    return $altered;
}

# Implement if needed
#sub dot_syntax_collapse {
#    my ( $args, $limit_to ) = @_;
#}

# Make this mockable so we can exercise the presumed-unreachable error condition.
sub _sort_keys {
    my ($args) = @_;
    my @sorted = sort keys %$args;    # separate assignment to satisfy perlcritic ProhibitReturnSort policy
    return @sorted;
}

1;
