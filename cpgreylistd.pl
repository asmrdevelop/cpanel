#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - cpgreylistd.pl                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::CloseFDs      ();
use Cpanel::Exception     ();
use Cpanel::ForkAsync     ();
use Cpanel::Sys::Setsid   ();
use Cpanel::Services::Hot ();
use File::Path            ();
use Getopt::Param::Tiny   ();

use Cpanel::GreyList::Config ();

exit run( \@ARGV ) if not caller;

sub run {
    my $argv_ref = shift;
    my $param    = Getopt::Param::Tiny->new( { 'array_ref' => $argv_ref } );

    my $daemonize = $param->param('systemd') ? 0 : 1;

    my $PID_FILE = Cpanel::GreyList::Config::get_pid_file();
    my $conf_dir = Cpanel::GreyList::Config::get_conf_dir();
    File::Path::make_path($conf_dir) if !-d $conf_dir;

    if ( $param->param('status') ) {
        if ( my $pid = _already_running_pid($PID_FILE) ) {
            print "[+] cPGreyList is running with PID: '$pid'\n";
        }
        else {
            print "[!] cPGreyList is not running.\n";
        }
    }
    elsif ( $param->param('restart') ) {
        my $pid = _already_running_pid($PID_FILE);
        if ( !reload_cpgreylistd($pid) ) {
            stop_cpgreylistd($pid);
            start_cpgreylistd($daemonize);
        }
    }
    elsif ( $param->param('stop') ) {
        my $pid = _already_running_pid($PID_FILE);
        stop_cpgreylistd($pid);
    }
    elsif ( $param->param('start') ) {
        my $listen_fd = $param->param('listen');
        if ( my $pid = _already_running_pid($PID_FILE) ) {
            if ( !$listen_fd ) {
                print "[!] cPGreyList is already running with PID: '$pid'\n";
                return 1;    # Exit value
            }
        }
        start_cpgreylistd($daemonize);
    }
    else {
        usage();
    }
    return 0;    # Exit value
}

sub start_cpgreylistd {
    my $daemonize = shift // 1;

    if ($daemonize) {
        Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::Sys::Setsid::full_daemonize();
                Cpanel::CloseFDs::fast_closefds();
                exec( '/usr/local/cpanel/libexec/cpgreylistd', @ARGV );
            }
        ) || die Cpanel::Exception::create( 'IO::ForkError', [ error => $! ] );
    }
    else {
        exec( '/usr/local/cpanel/libexec/cpgreylistd', @ARGV );
    }
    return;
}

sub stop_cpgreylistd {
    my $pid = shift;

    if ($pid) {
        print "[*] Found cPGreyList running with PID: '$pid'. Stopping...\n";
        require Cpanel::Kill::Single;
        Cpanel::Kill::Single::safekill_single_pid($pid);
        print "[+] cPGreyList stopped successfully.\n";
    }
    else {
        print "[+] No running cPGreyList process found.\n";
    }

    return 1;
}

sub reload_cpgreylistd {
    my $pid = shift;
    if ($pid) {
        print "[*] cPGreyList is running with PID: '$pid'\n";
        if ( kill( 'HUP', $pid ) ) {
            print "[+] Successfully sent 'HUP' signal to daemon.\n";
            return 1;
        }
    }

    return;
}

sub usage {
    print <<EOF;
$0 - cPanel GreyListing Daemon

    --start     => Starts the daemon.
    --stop      => Stops the daemon.
    --restart   => Restarts the daemon.
    --status    => Displays the current status of daemon.

    --help      => show this help.
EOF
    exit 0;
}

#####################################
# PID Checking functions
# - copied from queueprocd
#####################################

#
# Test the supplied pidfile to see if the process is still alive.
#
#  $pidfile - pid file that we are testing
#  $pid - expected owner of the lockfile.
#
# Return the pid of the running process if the process is found to still be
# running, otherwise return a false value
sub _already_running_pid {
    my $pidfile = shift;

    return unless -e $pidfile;

    my $pid = Cpanel::Services::Hot::get_pid_from_file($pidfile);
    return 0 unless $pid;

    # if we can use kill to check the pid, it is best choice.
    my $fileuid = ( stat($pidfile) )[4];
    if ( $> == 0 || $> == $fileuid ) {

        # kill can return 0 on permissions problem, not just from missing process
        # Check the permissions. Despite the 'Errno' inclusion of %!, removing
        # it does not reduce the memory, it actually increases memory usage by
        # 72K in testing.
        return 0 unless kill( 0, $pid ) or $!{EPERM};
    }

    # If the proc filesystem is available, it's a good test.
    return ( -r "/proc/$pid" && $pid ) if -e "/proc/$$" && -r "/proc/$$";
    return;
}
#####################################
