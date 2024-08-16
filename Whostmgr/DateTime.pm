package Whostmgr::DateTime;

# cpanel - Whostmgr/DateTime.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
my @abbr = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

sub format_date {
    my $unixtime = shift || return;
    my ( $year, $month, $day, $hour, $min ) = ( localtime($unixtime) )[ 5, 4, 3, 2, 1 ];
    return wantarray ? ( sprintf( "%02d", $year % 100 ), $abbr[$month], $day, join( ':', sprintf( "%02d", $hour ), sprintf( "%02d", $min ) ) ) : join ' ', sprintf( "%02d", $year % 100 ), $abbr[$month], sprintf( "%02d", $day ), join( ':', sprintf( "%02d", $hour ), sprintf( "%02d", $min ) );
}

sub getyear  { return ( ( localtime( time() ) )[5] + 1900 ); }
sub getmonth { return ( ( localtime( time() ) )[4] + 1 ); }

sub iso_format {
    my $unixtime = shift || return;
    my ( $year, $month, $day, $hour, $min ) = ( localtime($unixtime) )[ 5, 4, 3, 2, 1 ];

    # zero-padding everything ensures a consistent output
    return ( $year + 1900 ) . '-' . sprintf( "%02d", ( $month + 1 ) ) . '-' . sprintf( "%02d", $day ) . ' ' . sprintf( "%02d", $hour ) . ':' . sprintf( "%02d", $min );
}
1;
