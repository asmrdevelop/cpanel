package Cpanel::DnsUtils::Stream;

# cpanel - Cpanel/DnsUtils/Stream.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cpanel::Time ();

sub getnewsrnum {
    my ($sr) = @_;
    my $todaytime = Cpanel::Time::time2dnstime();
    if ( $sr && index( $sr, $todaytime ) == 0 ) {
        return ++$sr;
    }
    return $todaytime . '00';
}

sub upsrnumstream {
    my ($zone_data) = @_;
    if ($zone_data) {
        $zone_data =~ s/\(([\n\s]+)(\d+)([\s\n\;]+)/'(' . $1 . getnewsrnum($2) . $3/e;
    }
    return $zone_data;
}

1;
