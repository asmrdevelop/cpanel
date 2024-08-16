package Whostmgr::XMLUI::Ips;

# cpanel - Whostmgr/XMLUI/Ips.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::Ips        ();
use Whostmgr::XMLUI      ();
use Whostmgr::ApiHandler ();

sub listips {
    my $ipref = Whostmgr::Ips::get_detailed_ip_cfg();
    Whostmgr::XMLUI::xmlencode($ipref);
    my %RS;
    $RS{'result'} = $ipref;
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'listips', NoAttr => 1 );
}

sub addip {
    my %OPTS    = @_;
    my $ip      = $OPTS{'ip'};
    my $netmask = $OPTS{'netmask'};

    my ( $status, $statusmsg, $msgref, $errmsg ) = Whostmgr::Ips::addip( $ip, $netmask );

    # $msgref is an array of messages. Whostmgr::ApiHandler will add multiple msgs to the output. Need to combine them.
    my $messages;
    foreach my $msgs_line ( @{$msgref} ) {
        chomp $msgs_line;
        $messages .= $msgs_line . "\n";
    }
    chomp $messages;    # remove trailing newline

    my @RSD = ( { 'status' => $status, 'statusmsg' => $statusmsg, 'msgs' => $messages, 'errors' => $errmsg } );
    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'addip'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'addip', 'NoAttr' => 1 );
}

sub delip {
    my %OPTS             = @_;
    my $ip               = $OPTS{'ip'};
    my $ethernetdev      = $OPTS{'ethernetdev'};
    my $skip_if_shutdown = $OPTS{'skipifshutdown'};

    my ( $status, $statusmsg, $warnref ) = Whostmgr::Ips::delip( $ip, $ethernetdev, $skip_if_shutdown );

    my @RSD = ( { 'status' => $status, 'statusmsg' => $statusmsg, 'warnings' => $warnref } );
    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'delip'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, 'RootName' => 'delip', 'NoAttr' => 1 );
}

1;
