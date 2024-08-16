package Whostmgr::DNS::DNSSEC;

# cpanel - Whostmgr/DNS/DNSSEC.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DNSSEC::Available ();

sub fetch_domains_with_dnssec {
    return [] if !Cpanel::DNSSEC::Available::dnssec_is_available();

    # Avoid creating the nameserver config object before we are sure, as the
    # 'initialize' process will perform checks that can be expensive.
    require Cpanel::NameServer::Conf::PowerDNS;
    return Cpanel::NameServer::Conf::PowerDNS->new()->fetch_domains_with_dnssec();
}

1;
