package Cpanel::Sys::Load;

# cpanel - Cpanel/Sys/Load.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Sys::Info ();

our $ForceFloat = 1;

sub getloadavg {
    my ($force_float) = @_;

    my $sysinfo = Cpanel::Sys::Info::sysinfo();

    return ( sprintf( '%0.2f', $sysinfo->{'load1'} ), sprintf( '%0.2f', $sysinfo->{'load5'} ), sprintf( '%0.2f', $sysinfo->{'load15'} ) ) if $force_float;
    return ( $sysinfo->{'load1'},                     $sysinfo->{'load5'},                     $sysinfo->{'load15'} );
}

1;
