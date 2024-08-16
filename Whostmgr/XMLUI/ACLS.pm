package Whostmgr::XMLUI::ACLS;

# cpanel - Whostmgr/XMLUI/ACLS.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::ACLS       ();
use Whostmgr::ApiHandler ();

sub myprivs {

    my %RS;
    $RS{'privs'} = \%Whostmgr::ACLS::ACL;

    return Whostmgr::ApiHandler::out( \%RS, RootName => 'myprivs', NoAttr => 1 );
}

sub listacls {

    my $aclref = Whostmgr::ACLS::list_acls();

    my %RS;
    $RS{'acls'} = $aclref;

    return Whostmgr::ApiHandler::out( \%RS, RootName => 'listacls', NoAttr => 1 );
}

sub saveacllist {
    my %OPTS = @_;

    my ( $result, $reason ) = Whostmgr::ACLS::save_acl_list(%OPTS);

    my @RSD;
    push @RSD, { status => $result, statusmsg => $reason };
    my %RS;
    $RS{'results'} = \@RSD;

    return Whostmgr::ApiHandler::out( \%RS, RootName => 'saveacllist', NoAttr => 1 );
}

1;
