package Cpanel::DnsUtils::Exists;

# cpanel - Cpanel/DnsUtils/Exists.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DnsUtils::AskDnsAdmin ();

sub domainexists {
    my $ndomain = shift;
    return 0 if !$ndomain || ref $ndomain;    # Domains called '', 0, or undef don't exist. That's silly.
    if ( Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( "ZONEEXISTS", 0, $ndomain ) ) {
        return 1;
    }

    return 0;
}

1;
