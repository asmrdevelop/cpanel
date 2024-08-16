package Cpanel::DnsUtils::GenericRdata;

# cpanel - Cpanel/DnsUtils/GenericRdata.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::CAA

=head1 SYNOPSIS

    my $str = Cpanel::DnsUtils::GenericRdata::encode($rdata);

    my $rdata = Cpanel::DnsUtils::GenericRdata::decode($str);

=head1 DESCRIPTION

This module contains logic for handling DNS RDATA in its generic
hex encoding, as described in L<RFC 3597|https://tools.ietf.org/html/rfc3597>.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $text = encode($RDATA)

$RDATA is an octet string of the resource record’s raw RDATA.

=cut

sub encode ($rdata) {

    # We uppercase the hex-encoded rdata for legacy reasons.
    # RFC 3597 doesn’t require it.
    return ( "\\# " . length($rdata) . ( length($rdata) ? ' ' . ( unpack( 'H*', $rdata ) =~ tr<a-f><A-F>r ) : q<> ) );
}

=head2 $rdata = decode($TEXT)

The inverse of C<encode()>. (This may not actually be useful for
cPanel & WHM in production?)

=cut

sub decode ($encoded) {
    my ( $hdr, $len, @hex_words ) = split( q< >, $encoded, -1 );

    $hdr eq '\\#' or die "Bad generic RDATA header: [$encoded]";

    my ( $mismatch_yn, $joined_hex );

    if ( $len eq '0' ) {
        $mismatch_yn = !!@hex_words;
    }
    else {
        $joined_hex  = join( q<>, @hex_words );
        $mismatch_yn = ( 2 * $len ) != length($joined_hex);
    }

    die "Mismatched generic RDATA length: [$encoded]" if $mismatch_yn;

    return $len ? pack( 'H*', $joined_hex ) : q<>;
}

1;
