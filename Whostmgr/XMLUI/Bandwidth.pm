package Whostmgr::XMLUI::Bandwidth;

# cpanel - Whostmgr/XMLUI/Bandwidth.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Whostmgr::Bandwidth  ();
use Whostmgr::XMLUI      ();
use Whostmgr::ApiHandler ();

sub showbw {
    my %OPTS   = @_;
    my $status = 1;
    my %RS;

    if ( defined $OPTS{'month'} ) {
        my $month = $OPTS{'month'} + 0;

        if ( $month < 1 || $month > 12 ) {
            $status = $RS{'status'} = 0;
            $RS{'message'} = $RS{'statusmsg'} = 'Invalid month provided';
        }
    }
    if ( defined $OPTS{'year'} ) {
        my $year = $OPTS{'year'} + 0;

        if ( $year < 1970 || $year > 2200 ) {
            $status = $RS{'status'} = 0;
            $RS{'message'} = $RS{'statusmsg'} = 'Invalid year provided';
        }
    }
    if ($status) {
        my $rsd_ref = Whostmgr::Bandwidth::_showbw(%OPTS);

        Whostmgr::XMLUI::xmlencode($rsd_ref);

        $RS{'bandwidth'} = $rsd_ref;
    }

    return Whostmgr::ApiHandler::out( \%RS, RootName => 'showbw', NoAttr => 1 );
}

sub limitbw {
    my %OPTS = @_;

    my @RSD;
    my @status = Whostmgr::Bandwidth::setbwlimit( 'user' => $OPTS{'user'}, 'bwlimit' => $OPTS{'bwlimit'} );
    push( @RSD, { status => $status[0], statusmsg => $status[1], 'bwlimit' => $status[2] } );

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'result'} = \@RSD;

    return Whostmgr::ApiHandler::out( \%RS, RootName => 'limitbw', NoAttr => 1 );

}

1;
