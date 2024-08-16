package Cpanel::NSCD::Check;

# cpanel - Cpanel/NSCD/Check.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::NSCD::Constants     ();
use Cpanel::Socket::UNIX::Micro ();

our $CACHE_TTL = 600;

my $last_check_time = 0;
my $nscd_is_running_cache;

sub nscd_is_running {
    my $now = time();
    if ( $last_check_time && $last_check_time + $CACHE_TTL > $now ) {
        return $nscd_is_running_cache;
    }

    $last_check_time = $now;
    my $socket;
    if ( Cpanel::Socket::UNIX::Micro::connect( $socket, $Cpanel::NSCD::Constants::NSCD_SOCKET ) ) {
        return ( $nscd_is_running_cache = 1 );
    }
    return ( $nscd_is_running_cache = 0 );
}

1;
