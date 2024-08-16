
# cpanel - Whostmgr/CheckRun.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::CheckRun;

use strict;
use warnings;

sub check {
    my $system  = shift || "Undefined";
    my $log     = shift || "undefined";
    my $pidfile = shift;

    # Check if conversion is currently running
    if ( $pidfile && -e $pidfile && open my $sns_pid_fh, '<', $pidfile ) {
        my $pid = readline($sns_pid_fh);
        chomp $pid;
        close $sns_pid_fh;

        # Setupnameserver does a better pid check.  We just need something simple here for the interface and log file.
        if ( $pid =~ /^\d+$/ && -e '/proc/' . $pid ) {
            print "$system process is currently running.<br /><br />\n";
            print "Please wait for the current process to complete before attempting another.<br /><br />\n";
            print "A log of the conversion process is available at $log.<br /><br />\n";
            return 1;
        }
    }
    return 0;
}

1;
