package Whostmgr::XMLUI::Nameserver;

# cpanel - Whostmgr/XMLUI/Nameserver.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Whostmgr::ApiHandler ();
use Whostmgr::Nameserver ();

sub lookupnsip {
    my $nameserver = shift;
    my $ip         = Whostmgr::Nameserver::get_ip_from_nameserver($nameserver);
    return Whostmgr::ApiHandler::out( { 'ip' => $ip }, 'RootName' => 'lookupnsip', 'NoAttr' => 1 );
}

sub lookupnsips {
    my $nameserver = shift;
    my $ips        = Whostmgr::Nameserver::get_ips_for_nameserver($nameserver);
    return Whostmgr::ApiHandler::out( $ips, 'RootName' => 'lookupnsips', 'NoAttr' => 1 );
}

1;
