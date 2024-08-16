package Cpanel::IPv6::RFC5952;

# cpanel - Cpanel/IPv6/RFC5952.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::IPv6::RFC5952

=head1 SYNOPSIS

    my $formatted = Cpanel::IPv6::RFC5952::convert($ipv6_text);

=head1 DESCRIPTION

L<RFC 5952|https://tools.ietf.org/html/rfc5952#section-4> defines a
recommended standard notation for IPv6 addresses. This module converts
any valid IPv6 address to that standard.

This is useful for public-facing APIs, as API consumers can then more
easily compare IPv6 addresses. Each valid IPv6 address has exactly one
representation in this format.

=cut

#----------------------------------------------------------------------

use Cpanel::IP::Convert ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 convert( $TEXT )

Converts any text representation of an IPv6 address to its
RFC 5952 form.

Behavior is undefined if $TEXT is not an already-valid IPv6 address.
An attempt is made to C<die()> in such cases, but it’s by no means complete.

=cut

sub convert ($text) {
    _sanity_validate($text);

    my $expanded = Cpanel::IP::Convert::normalize_human_readable_ip($text);
    $expanded =~ tr<A-F><a-f>;

    my @words = split m<:>, $expanded;

    # Strip leading zeros from each word.
    s<\A0{1,3}><> for @words;

    my @zeros_at = grep { $words[$_] eq '0' } 0 .. $#words;

    my $zero_run_at;
    my $zero_run_length = 1;

    for my $i ( 0 .. $#words ) {
        next if $words[$i] ne '0';

        my $runlength = 1;

        for my $ii ( ( 1 + $i ) .. $#words ) {
            last if $words[$ii] ne '0';
            $runlength++;
        }

        if ( $runlength > $zero_run_length ) {
            $zero_run_length = $runlength;
            $zero_run_at     = $i;
        }
    }

    if ( defined $zero_run_at ) {

        # Special case: all zeros:
        if ( $zero_run_length == @words ) {
            @words = (q<>) x 3;
        }
        else {
            splice @words, $zero_run_at, $zero_run_length, q<>;

            if ( 0 == $zero_run_at ) {
                unshift @words, q<>;
            }
            elsif ( $words[-1] eq q<> ) {
                push @words, q<>;
            }
        }
    }

    return join( ':', @words );
}

sub _sanity_validate ($text) {

    # Only 1 :: sequence is allowed
    my $is_invalid = ( index( $text, '::' ) != rindex( $text, '::' ) );

    die "Invalid IPv6 address: “$text”" if $is_invalid;

    return;
}

1;
