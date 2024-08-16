package Cpanel::DNS::Rdata;

# cpanel - Cpanel/DNS/Rdata.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DNS::Rdata - Light, pure-Perl DNS RDATA parser

=head1 SYNOPSIS

    my $rdata = [
        "\3ns1\7example\3com\0",
        "\3ns2\7example\3com\0",
    ];

    Cpanel::DNS::Rdata::parse_2($rdata);

    # $rdata is now: [ qw( ns1.example.com  ns2.example.com ) ]

=cut

#----------------------------------------------------------------------

use DNS::Unbound ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

This module implements the following:

=head2 parse_1(\@RECORDS)

(A) Converts @RECORDS to IPv4 dotted notation.

=cut

# (cheap inet_ntoa())
sub parse_1 {
    @{ $_[0] } = map { join '.', unpack( 'C4', $_ ) } @{ $_[0] };

    return;
}

*parse_a = *parse_1;

=head2 parse_28(\@RECORDS)

(AAAA) Converts @RECORDS to fully-expanded IPv6 hex notation.

=cut

# (cheap inet_ntop())
sub parse_28 {
    @{ $_[0] } = map { join ':', unpack( '(H4)*', $_ ) } @{ $_[0] };

    return;
}

*parse_aaaa = *parse_28;

=head2 parse_15(\@RECORDS_AR)

(MX) Converts @RECORDS_AR to array references: [ priority, exchange ].

=cut

sub parse_15 {
    for my $rr ( @{ $_[0] } ) {
        $rr = [ unpack 'na*', $rr ];
        $rr->[1] = DNS::Unbound::decode_name( $rr->[1] );

        substr( $rr->[1], -1 ) eq '.' && chop $rr->[1];
    }

    return;
}

=head2 parse_2(\@RECORDS_AR)

(NS) Converts @RECORDS_AR to DNS names (no trailing C<.>).

=cut

sub parse_2 {
    $_ = DNS::Unbound::decode_name($_) for @{ $_[0] };

    substr( $_, -1 ) eq '.' && chop for @{ $_[0] };

    return;
}

=head2 parse_12(\@RECORDS_AR)

(PTR) Same as C<parse_2()>.

=cut

=head2 parse_5(\@RECORDS_AR)

(CNAME) Same as C<parse_2()>.

=cut

# PTR, CNAME
*parse_12 = *parse_5 = *parse_2;

=head2 parse_16(\@RECORDS_AR)

(TXT) Converts @RECORDS_AR to array references of strings.

(NB: A TXT record is a B<list> of strings, B<NOT> a simple string.)

=cut

sub parse_16 {
    $_ = DNS::Unbound::decode_character_strings($_) for @{ $_[0] };

    return;
}

=head2 parse_6(\@RECORDS_AR)

(SOA) Converts @RECORDS_AR to array references of values
as RFC 1035 describes for SOA records.

=cut

sub parse_6 {
    $_ = [ unpack '(Z*)2 N5', $_ ] for @{ $_[0] };

    for my $rec_ar ( @{ $_[0] } ) {

        # This doesn’t need a chop() after it because the Z* in the
        # unpack template above leaves it out.
        $_ = DNS::Unbound::decode_name($_) for @{$rec_ar}[ 0, 1 ];
    }

    return;
}

=head2 parse_257(\@RECORDS_AR)

(CAA) Converts @RECORDS_AR to array references of values.
See L<Cpanel::DnsUtils::CAA>’s C<decode_data()> function for the
exact definition.

=cut

sub parse_257 {
    local ( $@, $! );
    require Cpanel::DnsUtils::CAA;

    $_ = [ Cpanel::DnsUtils::CAA::decode_rdata($_) ] for @{ $_[0] };

    return;
}

1;
