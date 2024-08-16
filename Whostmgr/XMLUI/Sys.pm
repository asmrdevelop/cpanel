package Whostmgr::XMLUI::Sys;

# cpanel - Whostmgr/XMLUI/Sys.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::Sys         ();
use Cpanel::Sys::Hostname ();
use Whostmgr::ApiHandler  ();

sub gethostname {

    my %RS;
    $RS{'hostname'} = Cpanel::Sys::Hostname::gethostname();
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'gethostname', NoAttr => 1 );
}

sub reboot {
    my %OPTS = @_;
    my %RS;
    $RS{'reboot'} = 'normal';
    if ( $OPTS{'force'} == 1 ) {
        $RS{'reboot'} = 'force';
        Whostmgr::Sys::forcereboot();
    }
    else {
        Whostmgr::Sys::reboot();
    }
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'reboot', NoAttr => 1 );
}

1;
