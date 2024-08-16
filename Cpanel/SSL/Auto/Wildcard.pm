package Cpanel::SSL::Auto::Wildcard;

# cpanel - Cpanel/SSL/Auto/Wildcard.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Wildcard

=head1 DESCRIPTION

This module exists for use by AutoSSL providers that can issue certificates
that contain wildcard domains. Note that this does I<not> include AutoSSL’s
default cPanel/Sectigo provider; thus, nothing in the mainline cPanel & WHM
code calls into this module.

NB: As of this writing, cPanel’s Let’s Encrypt provider plugin is this
module’s only consumer. The code is here rather than in that plugin because
this is generic logic for any wildcard-capable AutoSSL provider, not just
Let’s Encrypt.

=cut

#----------------------------------------------------------------------

use Cpanel::PublicSuffix   ();
use Cpanel::WildcardDomain ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @wildcards = find_reducer_wildcards( @DOMAINS )

Identifies all wildcard domains that can reduce the number of domains
needed to refer to all of @DOMAINS. For this function’s purpose, a
wildcard only counts toward a I<single> label (à la TLS rather than DNS).

For example, if @DOMAINS are C<example.com>, C<a.example.com>,
C<b.example.com>, C<other-domain.com>, and C<www.other-domain.com>,
this will return C<*.example.com>.

(This will B<NOT> return TLD wildcards, so C<*.com> will not be returned.)

=cut

sub find_reducer_wildcards (@domains) {
    my %wildcard_count;

    my %wc_first_index;

    for my $d ( 0 .. $#domains ) {
        my $domain = $domains[$d];

        next if index( $domain, '.' ) == -1;

        my ($as_wildcard) = Cpanel::WildcardDomain::to_wildcards($domain);

        $wc_first_index{$as_wildcard} //= $d;

        $wildcard_count{$as_wildcard}++;
    }

    my @reducer_wildcards;

    my @all_wildcards    = keys %wildcard_count;
    my @sorted_wildcards = sort { $wc_first_index{$a} <=> $wc_first_index{$b} } @all_wildcards;

    for my $wildcard (@sorted_wildcards) {
        if ( $wildcard_count{$wildcard} > 1 ) {
            push @reducer_wildcards, $wildcard;
        }
    }

    my @non_tld_reducer_wildcards = grep { !Cpanel::PublicSuffix::domain_isa_tld( substr( $_, 2 ) ); } @reducer_wildcards;

    return @non_tld_reducer_wildcards;
}

=head2 @reduced = reduce_domains_by_wildcards( \@DOMAINS, @WILDCARDS )

Copies @DOMAINS and reduces it for each @WILDCARDS thus: the first domain
that matches a particular wildcard will be replaced with $WILDCARD;
subsequent domains that match the wildcard will be removed.

Returns the copied @DOMAINS, after reductions.

=cut

sub reduce_domains_by_wildcards ( $domains_ar, @wildcards ) {
    my @reduced = @$domains_ar;

    for my $wildcard (@wildcards) {
        die "Bad wildcard: [$wildcard]" if 0 != rindex( $wildcard, '*.', 0 );

        my @indexes;

        for my $d ( 0 .. $#reduced ) {
            if ( ( Cpanel::WildcardDomain::to_wildcards( $reduced[$d] ) )[0] eq $wildcard ) {
                push @indexes, $d;
            }
        }

        if (@indexes) {

            my $first_index = shift @indexes;
            $reduced[$first_index] = $wildcard;

            for my $d ( reverse @indexes ) {
                splice( @reduced, $d, 1 );
            }

        }
    }

    return @reduced;
}

=head2 substitute_wildcard_for_domains( $WILDCARD, \@DOMAINS )

Alters @DOMAINS in-place: the first domain that matches $WILDCARD
will be replaced with $WILDCARD; subsequent domains that match
$WILDCARD will be removed.

Returns nothing.

This function is redundant with C<reduce_domains_by_wildcards()>.
It is retained for compatibility; please use C<reduce_domains_by_wildcards()>
in all new code.

=cut

sub substitute_wildcard_for_domains ( $wildcard, $domains_ar ) {
    @$domains_ar = reduce_domains_by_wildcards( $domains_ar, $wildcard );

    return;
}

1;
