package Cpanel::QuickZoneFetch;

# cpanel - Cpanel/QuickZoneFetch.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::ZoneFile              ();
use Cpanel::DnsUtils::AskDnsAdmin ();

sub fetch ($domain) {

    my @ZFILE = split( "\n", Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "GETZONE", 0, $domain ) );

    return Cpanel::ZoneFile->new( text => \@ZFILE, domain => $domain );
}

1;
