package Whostmgr::Ips::Shared;

# cpanel - Whostmgr/Ips/Shared.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles             ();
use Cpanel::Validate::IP::v4        ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::StringFunc::Trim        ();

sub get_shared_ip_address_for_creator {
    my ( $creator, $wwwacctconf_ref ) = @_;

    if ( length $creator && open my $ownermainip_fh, '<', "$Cpanel::ConfigFiles::MAIN_IPS_DIR/$creator" ) {
        my $mip = readline $ownermainip_fh;
        chomp $mip;
        Cpanel::StringFunc::Trim::ws_trim( \$mip );
        close $ownermainip_fh;
        return $mip if Cpanel::Validate::IP::v4::is_valid_ipv4($mip);
    }

    $wwwacctconf_ref ||= Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    return $wwwacctconf_ref->{'ADDR'};
}
1;
