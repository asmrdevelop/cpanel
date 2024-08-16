package Cpanel::Sys::Kernel;

# cpanel - Cpanel/Sys/Kernel.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#

use strict;
use Cpanel::Fcntl::Constants ();

our @KNOWN_PRINTK_LOCATIONS = qw(/sys/module/printk/parameters/time /sys/module/printk/parameters/printk_time);
###########################################################################
#
# Method:
#   enable_printk_timestamps
#
# Description:
#   Enables timestamps from kernel messages.  This is currently
#   used by Cpanel::Sys::OOM to determine when a process is invoking
#   OOM-killer
#
# Returns:
#   1 if timestamps are enabled
#   0 if timestamps could not be enabled
#
sub enable_printk_timestamps {
    foreach my $possible_printk_location (@KNOWN_PRINTK_LOCATIONS) {
        if ( sysopen( my $fh, $possible_printk_location, $Cpanel::Fcntl::Constants::O_WRONLY ) ) {
            if ( print {$fh} "1" ) {
                return 1;
            }
        }
    }
    return 0;
}
1;
