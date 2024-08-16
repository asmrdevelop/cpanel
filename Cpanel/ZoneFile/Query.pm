package Cpanel::ZoneFile::Query;

# cpanel - Cpanel/ZoneFile/Query.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::Query

=head1 SYNOPSIS

To get the first SOA record in the file:

    my $rr = Cpanel::ZoneFile::Query::first_of_type( $zonetext, '.', 'SOA' );

=head1 DESCRIPTION

This module implements “queries” against DNS zone files.

=head1 SEE ALSO

L<Cpanel::ZoneFile::Search> is a lighter, more naïve version of this module.
L<Cpanel::ZoneFile::Parse> is useful for parsing an I<entire> zone file.

=cut

#----------------------------------------------------------------------

BEGIN {

    # Bug in DNS::LDNS: “Subroutine DNS::LDNS::RData::compare redefined”.
    # “no warnings” doesn’t silence it, so we have to discard it.
    # cf. https://rt.cpan.org/Public/Bug/Display.html?id=134388
    local $SIG{'__WARN__'} = sub { };

    require DNS::LDNS;
    require DNS::LDNS::RR;
    require DNS::LDNS::RData;
}

use Carp ();

use Cpanel::Autodie                    ();
use Cpanel::TempFH                     ();
use Cpanel::XSLib::File                ();
use Cpanel::ZoneFile::Parse::Constants ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $rr = first_of_type( $ZONETEXT, $ORIGIN, $TYPE )

Retrieves the first record of type $TYPE in $ZONETEXT.

Returns either a L<DNS::LDNS::RR> instance that represents that record
or undef if no such record was found.

Throws if any parse error occurs.

$ORIGIN is useful only to inform the C<dname()> attribute of the returned
object. If you don’t care about that, just give C<.> as the $ORIGIN.

For example, if you have C<example.com>’s zone file ($ZONETEXT),
and you want its serial number (i.e., from the SOA record), do:

    my $rr = first_of_type( $ZONETEXT, '.', 'SOA' );

=cut

sub first_of_type ( $zonetext, $origin, $type ) {
    utf8::downgrade($_) for ( $zonetext, $origin );

    my $typenum = DNS::LDNS::rr_type_by_name($type) || do {
        Carp::croak "Unknown record type: $type";
    };

    my $origin_rd = DNS::LDNS::RData->new( DNS::LDNS::LDNS_RDF_TYPE_DNAME(), $origin );
    my $prev      = $origin_rd->clone;
    my $ttl       = 0;

    # Unfortunately LDNS doesn’t seem to expose a means of parsing a zone
    # as a single string; it has to read it from a file.
    my $fh = Cpanel::TempFH::create();
    Cpanel::Autodie::syswrite_sigguard( $fh, $zonetext );
    Cpanel::Autodie::sysseek( $fh, 0, 0 );

    local $DNS::LDNS::last_status;

    while ( !_ldns_is_done_reading($fh) ) {
        my $rr = DNS::LDNS::RR->new(
            file        => $fh,
            default_ttl => \$ttl,
            origin      => \$origin_rd,
            prev        => \$prev,
        );

        if ($rr) {
            next if $rr->type() != $typenum;

            return $rr;
        }
        elsif ( !exists $Cpanel::ZoneFile::Parse::Constants::EXPECTED_STATUS{$DNS::LDNS::last_status} ) {
            my $errstr = DNS::LDNS::errorstr_by_id($DNS::LDNS::last_status);

            die "Failed to parse DNS zone: $errstr";
        }
    }

    return undef;
}

# See note about this logic in Cpanel::ZoneFile::Parse.
*_ldns_is_done_reading = *Cpanel::XSLib::File::feof;

1;
