package Cpanel::IpPool;

# cpanel - Cpanel/IpPool.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles           ();
use Cpanel::DIp::MainIP           ();
use Cpanel::Server::Type::License ();
use Cpanel::Ips::Fetch            ();
use Cpanel::HttpUtils::AllIps     ();
use Cpanel::FileUtils::Write      ();

sub rebuild {
    my $mainip = Cpanel::DIp::MainIP::getmainip();
    my %IPS    = Cpanel::Ips::Fetch::fetchipslist();

    if ( open my $reservedips_fh, '<', $Cpanel::ConfigFiles::RESERVED_IPS_FILE ) {
        while ( my $reservedip = readline($reservedips_fh) ) {
            $reservedip =~ s/[\r\n]*//g;
            delete $IPS{$reservedip};
        }
        close $reservedips_fh;
    }

    if ( Cpanel::Server::Type::License::is_ea4_allowed() ) {
        my @http_ips = Cpanel::HttpUtils::AllIps::get_all_ipv4s();
        delete @IPS{ @http_ips, $mainip };
    }

    my @freeips = sort { $b cmp $a } grep { $IPS{$_} == 1 } keys %IPS;
    Cpanel::FileUtils::Write::overwrite(
        $Cpanel::ConfigFiles::IP_ADDRESS_POOL_FILE,
        join( "\n", @freeips, q<> ),    #trailing newline
        0644,
    );
    return scalar @freeips;
}

1;
