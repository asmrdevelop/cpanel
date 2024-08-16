package Whostmgr::DNS::Zone;

# cpanel - Whostmgr/DNS/Zone.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DnsUtils::AskDnsAdmin  ();
use Cpanel::Validate::Domain::Tiny ();
use Cpanel::ZoneFile               ();

sub fetchdnszone {
    my $zone  = shift;
    my @ZFILE = split( "\n", Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'GETZONE', 0, $zone ) );

    if (wantarray) { return @ZFILE; }
    return \@ZFILE;
}

sub _bump_serial_number {
    my $zonefile = shift;

    return $zonefile->increase_serial_number();
}

sub get_zone_records_by_type {
    my ( $records_ref, $domain, $type ) = @_;

    if ( !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        return 0, 'Invalid domain specified.';
    }

    my $lines_ref = fetchdnszone($domain);
    if ( !$lines_ref ) {
        return 0, 'No data read from zone file.';
    }
    my $zonefile = Cpanel::ZoneFile->new( 'domain' => $domain, 'text' => $lines_ref );

    if ( 0 == $zonefile->{'status'} ) {
        return 0, $zonefile->{'error'};
    }

    my $records = $zonefile->find_records( 'type' => $type );
    @$records_ref = @$records;
    return 1, 'Records obtained.';
}

1;
