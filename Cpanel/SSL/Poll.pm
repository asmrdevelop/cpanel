package Cpanel::SSL::Poll;

# cpanel - Cpanel/SSL/Poll.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub next_poll_time_dv {
    my ( $request_time, $last_poll_time ) = @_;

    return _next_poll( 'dv', $request_time, $last_poll_time );
}

sub next_poll_time_ov {
    my ( $request_time, $last_poll_time ) = @_;

    return _next_poll( 'ov', $request_time, $last_poll_time );
}

sub next_poll_time_ev {
    my ( $request_time, $last_poll_time ) = @_;

    return _next_poll( 'ev', $request_time, $last_poll_time );
}

#----------------------------------------------------------------------

my $_MINUTE = 60;
my $_HOUR   = 60 * $_MINUTE;

our $_NOW_FOR_TESTING;
sub _now { return $_NOW_FOR_TESTING || time }

sub _next_poll {
    my ( $val_lvl, $request_time, $last_poll_time ) = @_;

    my $now = _now();

    my $interval = __PACKAGE__->can("_poll_interval_$val_lvl")->( $now - $request_time );

    return $last_poll_time + $interval;
}

sub _poll_interval_ov {
    my ($time_in_queue) = @_;

    # The polling interval for OV and EV is designed to catch action URL
    # updates as well as certificate issuances
    # (whereas for DV we only care about issuance).

    #After a day, every hour.
    if ( $time_in_queue >= ( 24 * $_HOUR ) ) {
        return $_HOUR;
    }

    #After 4 hours, every 30 minutes.
    if ( $time_in_queue >= ( 4 * $_HOUR ) ) {
        return $_HOUR / 2;
    }

    #Every 5 minutes at first.
    return 5 * $_MINUTE;
}

#For now at least, poll for EV on the same frequency as OV.
*_poll_interval_ev = \&_poll_interval_ov;

sub _poll_interval_dv {
    my ($time_in_queue) = @_;

    #After a day, every 12 hours.
    if ( $time_in_queue >= ( 24 * $_HOUR ) ) {
        return 12 * $_HOUR;
    }

    #After 4 hours, every hour.
    if ( $time_in_queue >= ( 4 * $_HOUR ) ) {
        return $_HOUR;
    }

    #After 1 hour, every 30 minutes.
    if ( $time_in_queue >= $_HOUR ) {
        return 30 * $_MINUTE;
    }

    #Every 5 minutes at first.
    return 5 * $_MINUTE;
}

1;
