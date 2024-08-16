package Whostmgr::XMLUI::Packages;

# cpanel - Whostmgr/XMLUI/Packages.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Features        ();
use Whostmgr::Packages::Mod ();
use Whostmgr::XMLUI         ();
use Whostmgr::ApiHandler    ();

sub listpkgs {
    my %OPTS = @_;
    require Whostmgr::Packages;
    my @RSD = Whostmgr::Packages::_listpkgs(%OPTS);
    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS = ( 'package' => \@RSD );
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'listpkgs', NoAttr => 1 );
}

sub addpkg {
    my %OPTS = @_;
    my @RSD;
    my ( $result, $reason, @status ) = Whostmgr::Packages::Mod::_addpkg(%OPTS);
    push @RSD, { status => $result, statusmsg => $reason, @status };
    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS = ( 'result' => \@RSD );
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'addpkg', NoAttr => 1 );
}

sub editpkg {
    my %OPTS = @_;
    my @RSD;
    my ( $result, $reason, @status ) = Whostmgr::Packages::Mod::_editpkg(%OPTS);
    push @RSD, { status => $result, statusmsg => $reason, @status };
    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS = ( 'result' => \@RSD );
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'editpkg', NoAttr => 1 );
}

sub killpkg {
    my %OPTS = @_;
    my @RSD;
    require Whostmgr::Packages;
    my ( $result, $reason, @status ) = Whostmgr::Packages::_killpkg(%OPTS);
    push @RSD, { status => $result, statusmsg => $reason };
    Whostmgr::XMLUI::xmlencode( \@RSD );
    my %RS = ( 'result' => \@RSD );
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'killpkg', NoAttr => 1 );
}

1;
