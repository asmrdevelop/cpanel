package Cpanel::DnsUtils::Name;

# cpanel - Cpanel/DnsUtils/Name.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Name - Utilities to handle DNS names

=head1 SYNOPSIS

    my $match_name = get_longest_short_match( $long_name, \@short_names );

    my $ancestor_hr = identify_ancestor_domains( \@names );

    is_subdomain_of( 'foo.bar.com', 'bar.com' );    #truthy
    is_subdomain_of( 'foo.bar.com', 'barrr.com' );  #falsy

=head1 FUNCTIONS

=head2 get_longest_short_match( LONG_NAME, \@SHORT_NAMES )

This finds the longest member of @SHORT_NAMES that matches the right-side
labels of LONG_NAME.

A practical application of this logic is to find which
of a list of zone names (@SHORT_NAMES) is the best match for a given domain
name (LONG_NAME).

This function considers equal strings to be a match.

If there is no match, then undef is returned.

=cut

sub get_longest_short_match {
    my ( $long_name, $short_names_ar ) = @_;

    my @matching_names = sort { length $b <=> length $a } grep { $_ eq $long_name or is_subdomain_of( $long_name, $_ ) } @$short_names_ar;

    return $matching_names[0];
}

=head2 identify_ancestor_domains( \@NAMES )

This identifies which members of @NAMES are subdomains of
other @NAMES members.

Returns a hash reference whose keys are the subdomains and the
values the associated ancestor domains.

The shortest ancestor domain is always returned; e.g., if
C<foo.bar.baz.com>, C<bar.baz.com>, and C<baz.com> are given,
C<foo.bar.baz.com> will point to C<baz.com> in the returned hash
reference even though C<foo.bar.baz.com>’s immediate parent domain
is C<bar.baz.com>.

=cut

sub identify_ancestor_domains {
    my ($names_ar) = @_;

    # This can be called many thousands of times during some
    # operations, so it’s worthwhile to optimize it.

    my %all_names;
    @all_names{@$names_ar} = ();

    my %ancestor;

  MAYBE_SUB:
    for my $maybe_sub ( grep { tr{.}{} > 1 } @$names_ar ) {
        my $ancestor_name = $maybe_sub;

        # Iterate through all of $maybe_sub’s parent domains,
        # longest to shortest.
        while ( ( $ancestor_name =~ tr<.><> ) > 1 ) {

            # Chop off the leading label.
            substr( $ancestor_name, 0, 1 + index( $ancestor_name, '.' ) ) = q<>;

            # If we already found an ancestor for $ancestor_name,
            # then we can just take that value and be done looping through
            # ancestors of the current $maybe_sub.
            if ( $ancestor{$ancestor_name} ) {
                $ancestor{$maybe_sub} = $ancestor{$ancestor_name};
                next MAYBE_SUB;
            }

            # This does NOT have a “next MAYBE_SUB” because we might find
            # that a shorter-yet $ancestor_name is also in @$names_ar.
            # If that happens, we’ll catch it on a subsequent run through
            # this current loop.
            if ( exists $all_names{$ancestor_name} ) {
                $ancestor{$maybe_sub} = $ancestor_name;
            }
        }
    }

    return \%ancestor;
}

=head2 is_subdomain_of( MAYBE_SUB, MAYBE_ANCESTOR )

Returns a boolean that indicates whether MAYBE_SUB is a subdomain
of MAYBE_ANCESTOR.

Sameness is B<not> considered to be a subdomain relationship here.

=cut

sub is_subdomain_of {
    return ( ( rindex( $_[0], $_[1] ) == ( length( $_[0] ) - length( $_[1] ) ) ) && ( ( substr( $_[0], length( $_[0] ) - length( $_[1] ) - 1, 1 ) eq '.' ) ) );
}

1;
