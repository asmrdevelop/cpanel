package Whostmgr::XMLUI::Guts;

# cpanel - Whostmgr/XMLUI/Guts.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::ApiHandler ();

sub applist {
    my $applist = shift;
    my %RS;
    $RS{'app'} = $applist;

    return Whostmgr::ApiHandler::out( \%RS, RootName => 'applist', NoAttr => 1 );
}

1;
