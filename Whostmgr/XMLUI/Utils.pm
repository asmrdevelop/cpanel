package Whostmgr::XMLUI::Utils;

# cpanel - Whostmgr/XMLUI/Utils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Sys::Load    ();
use Whostmgr::ApiHandler ();

sub loadavg {

    my %RS;
    ( $RS{'one'}, $RS{'five'}, $RS{'fifteen'} ) = Cpanel::Sys::Load::getloadavg($Cpanel::Sys::Load::ForceFloat);

    return Whostmgr::ApiHandler::out( \%RS, RootName => 'loadavg', NoAttr => 1 );
}

sub denied {
    my $app = shift || 'unknown';
    return Whostmgr::ApiHandler::out( { 'status' => 0, 'statusmsg' => 'Permission Denied', }, RootName => $app, NoAttr => 1 );
}

1;
