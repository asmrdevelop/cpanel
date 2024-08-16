package Cpanel::DnsUtils::Fetch;

# cpanel - Cpanel/DnsUtils/Fetch.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DnsUtils::AskDnsAdmin     ();
use Cpanel::DnsAdmin::Query::GETZONES ();

our $VERSION = '2.0';

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Fetch - Tools for fetching dns zones

=head1 SYNOPSIS

    use Cpanel::DnsUtils::Fetch;

    my $zone_ref = Cpanel::DnsUtils::Fetch::fetch_zones( 'zones' => [ 'zone1', 'zone2', ... ] );

=head2 WARNINGS

*INCOMPATIBLE CHANGE*

In cPanel v76 and later, fetch_zones returns the text of the zone file
as a scalar instead of an arrayref as the overhead proved to be too
expensive and resulted in upwards of 20% of the memory needed to restore
an account.

=head2 fetch_zones( 'zones' => [ 'zone1', 'zone2', ....], 'flags' => $flag );

=over 3

=item zones C<ARRAYREF>

    A list of zones to fetch

=item flags C<SCALAR>

    A flag to be passed to Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin

    $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL
    $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY
    $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_ONLY
    $Cpanel::DnsUtils::AskDnsAdmin::CORRELATIVE

    If no flag is passed, REMOTE_AND_LOCAL is assumed.

=back

Returns a hashref of dns zones with the name of the zone
as the key and the contents of the zone as a scalar.

Example

 {
   'zone1' => ';DNS zone\nblah IN A 5.5.5\n.....',
   'zone2' => ';DNS zone\nxxxx IN A 5.5.5\n.....',
    ....
 }

=cut

sub fetch_zones {
    my (%OPTS)  = @_;
    my $zone_ar = $OPTS{'zones'};
    my $flags   = $OPTS{'flags'} || 0;

    my $response_sr = Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin_sr( 'GETZONES', $flags, join( ',', @$zone_ar ) );

    return Cpanel::DnsAdmin::Query::GETZONES->parse_response($$response_sr);
}

1;
