package Cpanel::Sys::Hostname::Tiny;

# cpanel - Cpanel/Sys/Hostname/Tiny.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::LoadFile ();

my $hostname;
################################################################################
# gethostname
################################################################################
sub gethostname {
    return $hostname if $hostname;

    # Cpanel/Sys/Hostname.pm is faster if available
    if ( !$INC{'Cpanel/Sys/Hostname.pm'} ) {
        chomp( $hostname = Cpanel::LoadFile::loadfile( '/proc/sys/kernel/hostname', { 'skip_exists_check' => 1 } ) );
        if ($hostname) { return $hostname; }
        require Cpanel::Sys::Hostname;    # PPI NO PARSE - This is a conditional load
    }

    return ( $hostname = Cpanel::Sys::Hostname::gethostname() );
}

1;
