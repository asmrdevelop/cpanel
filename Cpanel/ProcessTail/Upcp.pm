#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/ProcessTail/Upcp.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ProcessTail::Upcp;

use strict;

use Cpanel::ProcessTail;
use Cpanel::CloseFDs        ();
use IO::Handle              ();
use Time::HiRes             ();
use Cpanel::Unix::PID::Tiny ();

our $log_dir = '/var/cpanel/updatelogs';
our $pid_dir = '/var/run';

sub log_it {
    my ($msg) = @_;

    print $msg;

    return;
}

sub run_tail {
    print qq{<script type="text/javascript">statusbox_modal=0;</script>\n};
    Cpanel::CloseFDs::fast_closefds();

    my $current_update_log = $log_dir . '/last';
    my $max                = 60;
    my $iter               = 0;

    # Wait till we're allowed to open it.
    my $fh;
    until ( defined $fh && fileno $fh ) {
        $fh = IO::Handle->new();
        if ( !open $fh, '<', $current_update_log ) {
            undef $fh;
            Time::HiRes::usleep($Cpanel::ProcessTail::sleeptime);    # sleep just a bit

            # try to open the last log file several times
            #    let some time for upcp to start
            if ( ++$iter > $max ) {
                log_it( '<p>Unable to find log file: ' . $current_update_log . '</p>' );
                return;
            }
        }
    }

    # pid must be checked after having a log
    #    in most cases except when a process is running for more than 6 hours...
    my $pid            = $pid_dir . '/upcp.pid';
    my $check_warnings = !-e $pid;
    if ( $check_warnings || $iter == $max ) {
        Cpanel::ProcessTail::print_log_line("The upcp process cannot be found. This will be the output from the last run.\n");
    }

    # avoid an infinite loop when the pid file exists
    #    and is not going to be removed
    my $upid = Cpanel::Unix::PID::Tiny->new();

    Cpanel::ProcessTail::process_log( $fh, $check_warnings, $pid, sub { return $upid->is_pidfile_running($pid) } );
    return;
}

1;
