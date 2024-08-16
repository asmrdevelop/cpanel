package Cpanel::DnsUtils::UpdateIps;

# cpanel - Cpanel/DnsUtils/UpdateIps.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DnsUtils::AskDnsAdmin ();
use Cpanel::LoadModule            ();

sub _ips_dnsmaster {
    return "/etc/ips.dnsmaster";
}

sub updatemasterips {
    my @MIPS = grep { length } split( /\n/, Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin("GETIPS"), 2 );

    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Write');

    return Cpanel::FileUtils::Write::overwrite( _ips_dnsmaster(), join( "\n", @MIPS ) . "\n", 0644 );
}

1;
