package Cpanel::DnsUtils::CAA;

# cpanel - Cpanel/DnsUtils/CAA.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::CAA

=head1 SYNOPSIS

    my @parsed = Cpanel::DnsUtils::CAA::decode_rdata($rdata);

    my $rdata = Cpanel::DnsUtils::CAA::encode_rdata( $flag, $tag, $value );

=head1 DESCRIPTION

This module contains logic for handling DNS CAA records.

=cut

#----------------------------------------------------------------------

use Cpanel::Context ();
use Cpanel::Set     ();

use constant _PACK_TEMPLATE => 'C C/a* a*';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $rdata = encode_rdata( $FLAG, $TAG, $VALUE )

Encodes the components of a CAA record to RDATA, suitable for sending
over the wire in a DNS response.

=cut

sub encode_rdata ( $flag, $tag, $value ) {
    return pack _PACK_TEMPLATE(), $flag, $tag, $value;
}

#----------------------------------------------------------------------

=head2 ($flag, $tag, $value) = decode_rdata( $RDATA )

The inverse of C<encode_rdata()>. Must be called in list context.

=cut

sub decode_rdata ($rdata) {
    Cpanel::Context::must_be_list();

    return unpack _PACK_TEMPLATE(), $rdata;
}

#----------------------------------------------------------------------

=head2 @ISSUERS = get_accepted_non_wildcard_issuers( \@CAA_STRINGS, \@RECORDS )

Returns the members of @CAA_STRINGS whom the given @RECORDS permit to
issue a certificate for a non-wildcard domain.

@RECORDS is an array of array references, each of which should match
the format that C<decode_rdata()> returns. It is understood that
this array was the RRSET from a DNS query for a specific (non-wilcard)
domain’s CAA records.

Each issuer is indicated by the C<issue> CAA record tag value.

@RECORDS may be empty.

=cut

sub get_accepted_non_wildcard_issuers ( $caa_strings, $rrset_ar ) {
    my $got = _match_rrset_to_caa_tag( $caa_strings, $rrset_ar, 'issue' );

    return $got || $caa_strings;
}

sub _match_rrset_to_caa_tag {
    my ( $caa_strings, $rrset_ar, $match_tag ) = @_;

    my ( @allowed, %allowed_uniq );

    my $has_match;

  RECORD:
    for my $rr_ar (@$rrset_ar) {
        my ( $flag, $tag, $value ) = @$rr_ar;

        # TODO: handle the flag?

        if ( $tag eq $match_tag ) {
            $has_match = 1;

            if ( $value ne ';' && !$allowed_uniq{$value}++ ) {
                push @allowed, $value;
            }
        }
    }

    return undef if !$has_match;

    my @whitelisted = Cpanel::Set::intersection(
        $caa_strings,
        \@allowed,
    );

    return \@whitelisted;
}

#----------------------------------------------------------------------

=head2 @ISSUERS = get_accepted_wildcard_issuers( \@RECORDS )

Like C<get_accepted_non_wildcard_issuers()> but determines the
permissibility of certificate issuance for a wildcard domain.

=cut

sub get_accepted_wildcard_issuers ( $caa_strings, $rrset_ar ) {
    my $got = _match_rrset_to_caa_tag( $caa_strings, $rrset_ar, 'issuewild' );

    # If there are no “issuewild” records, then just use the
    # non-wildcard logic.
    return $got || get_accepted_non_wildcard_issuers( $caa_strings, $rrset_ar );
}

1;
