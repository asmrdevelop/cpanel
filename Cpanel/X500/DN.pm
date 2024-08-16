package Cpanel::X500::DN;

# cpanel - Cpanel/X500/DN.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::X500::DN - Logic for RFC 2253 representation of Distinguished Names

=head1 SYNOPSIS

    my $dn_str = encode_kv_list_as_rdns(
        commonName => 'foo.org',
        organizationName => 'Some organization',
        weird => ' ha; ho  ',
    );

=head1 DESCRIPTION

This is a just-what-we-need implementation of logic that you can find in
CPAN’s L<X500::DN>.

=head1 FUNCTIONS

=head2 STR = encode_kv_list_as_rdns( TYPE1 => VALUE1, TYPE2 => VALUE2, ... )

This takes a list of key/value pairs and converts them to a single DN
string. Each key/value pair is treated as a single-value RDN. (Multi-value
RDNs don’t seem to be in very widespread use?)

This adds a space after each comma, which the RFC mandates that parsers
ignore; otherwise it serializes as the RFC’s examples show.

=cut

sub encode_kv_list_as_rdns {
    my (@kv_list) = @_;

    my @pieces;
    while ( my ( $type, $value ) = splice( @kv_list, 0, 2 ) ) {
        push @pieces, "$type=" . _escape_value_string($value);
    }

    #2.1: “... starting with the last element of the sequence
    #and moving backwards toward the first.”
    return join( ', ', reverse @pieces );
}

sub _escape_value_string {
    my ($str) = @_;

    $str =~ s<([,+"\\<>;])><\\$1>g;

    if ( substr( $str, -1 ) eq ' ' ) {
        substr( $str, -1 ) = '\\ ';
    }

    if ( ( index( $str, ' ' ) == 0 ) || ( index( $str, '#' ) == 0 ) ) {
        substr( $str, 0, 0, '\\' );
    }

    return $str;
}

1;
