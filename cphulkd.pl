#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - cphulkd.pl                              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package cphulkd;

BEGIN { unshift @INC, '/usr/local/cpanel'; }    ## no critic qw(RequireUseStrict RequireUseWarnings)

use cPstrict;

use Cpanel::SafeDir::MK   ();
use Cpanel::CloseFDs      ();
use Cpanel::Config::Hulk  ();
use Cpanel::Hulkd::Daemon ();
use Cpanel::Hulkd::Proc   ();
use Cpanel::Exception     ();
use Cpanel::ForkAsync     ();
use Cpanel::Sys::Setsid   ();
use Getopt::Param::Tiny   ();

our $HULK_VAR_DIR = '/var/cpanel/hulkd';

my @applist       = Cpanel::Hulkd::Proc::get_applist();
my $pids_expected = scalar @applist;

my $should_daemonize = 1;

exit( run( \@ARGV ) ? 0 : 1 ) if !caller();

sub run {
    my ($args_ar) = @_;

    my $params = Getopt::Param::Tiny->new( { 'array_ref' => $args_ar } );

    if ( !Cpanel::Config::Hulk::is_enabled() ) {

        if ( $params->param('notconfigured-ok') ) {
            print "cPHulkd is not configured.\n";
            return 1;
        }
        else {
            die "cPHulkd is not configured.\n";
        }
    }

    if ( $params->param('systemd') ) {
        $should_daemonize = 0;
    }

    if ( $params->param('stop') ) {
        stop();
    }
    elsif ( $params->param('reload') ) {
        reload();
    }
    elsif ( $params->param('restart') ) {
        stop();
        start();
    }
    elsif ( $params->param('status') ) {
        my @pids = status();
        if ( scalar @pids ) {
            print "cPHulkd is running with PID(s) @pids\n";
        }
        else {
            print "cPHulkd is not currently running.\n";
        }
    }
    else {
        start();
    }

    return 1;
}

sub start {

    my @pids = status();

    if ( scalar @pids == $pids_expected ) {
        die "cPHulkd is already running with PID(s) @pids\n";
    }
    elsif ( scalar @pids ) {
        print "cPHulkd is partially running with PID(s) @pids. Stopping...\n";
        Cpanel::Hulkd::Daemon::stop_daemons();
        print "cPHulkd stopped successfully.\n";
    }

    print "Starting cPHulkd...\n";

    foreach my $dir (qw( Cpanel/Hulkd/Detect Cpanel/Hulkd/Action )) {
        Cpanel::SafeDir::MK::safemkdir("$HULK_VAR_DIR/$dir") if !-d "$HULK_VAR_DIR/$dir";
    }

    my @exec_args = (
        -e '/var/cpanel/dormant_services/cphulkd/enabled' ? '/usr/local/cpanel/libexec/cphulkd-dormant' : '/usr/local/cpanel/libexec/cphulkd',
        @ARGV
    );

    if ($should_daemonize) {
        Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::CloseFDs::fast_closefds();
                Cpanel::Sys::Setsid::full_daemonize();
                exec @exec_args;
            }
        ) || die Cpanel::Exception::create( 'IO::ForkError', [ error => $! ] );
    }
    else {
        exec @exec_args;
    }

    print "Started.\n";

    return;
}

sub reload {
    my @pids = status();
    if ( scalar @pids ) {
        print "Reloading cPHulkd...\n";
        return Cpanel::Hulkd::Daemon::reload_daemons();
    }
    else {
        print "cPHulkd is not running.\n";
    }

    return 1;
}

sub stop {
    my @pids = status();
    if ( scalar @pids ) {
        print "cPHulkd is running with PID(s) @pids. Stopping...\n";
        Cpanel::Hulkd::Daemon::stop_daemons();
        print "cPHulkd stopped successfully.\n";
    }
    else {
        print "cPHulkd is not running.\n";
    }

    return 1;
}

sub status {
    my @pids;

    Cpanel::Hulkd::Daemon::exec_on_hulk_daemons(
        sub {
            my ( undef, undef, $current_pid ) = @_;

            push @pids, $current_pid if $current_pid;
        }
    );

    return @pids;
}

1;
