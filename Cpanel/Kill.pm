package Cpanel::Kill;

# cpanel - Cpanel/Kill.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Kill - Tools for sending signals to proccesses

=head1 SYNOPSIS

    use Cpanel::Kill;

    Cpanel::Kill::killall( 'HUP', 'cpanellogd', undef, undef, { 'root' => 1 } );

    Cpanel::Kill::killall( 'HUP', qr/^(?:cpsrvd|cpaneld|whostmgr|webmaild)/, undef, undef, { 'root' => 1 } );

=cut

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cpanel::PsParser        ();
use Cpanel::Signal::Numbers ();
use Cpanel::TimeHiRes       ();
our $VERBOSE = 1;

use constant _ESRCH => 3;

sub _verify_proc_mounted {
    if ( !-e "/proc/1" ) {
        return ( 0, "Critical Error: /proc is not mounted, and we do not have permission to mount it!" ) if $> != 0;
        print "Critical Error: /proc is not mounted)!\n";
        print "Attempting to mount /proc...";
        system( "mount", "-t", "procfs", "/proc", "/proc" );
        print "Done\n";
        if ( !-e "/proc/1" ) {
            return ( 0, "Critical Error: /proc is still not mounted!" );
        }

    }
    return ( 1, "Proc OK" );
}

=head2 safekill_multipid($pid_ar, $verbose, $wait_time_in_seconds)

Terminate all the processes listed in $pid_ar with SIGTERM.
If the processes fail to terminate cleanly with SIGTERM
they will be forcefully terminated with SIGKILL after
$wait_time_in_seconds.

The function will return 1 if all pids have been successfully
terminated.  If by some means one or more pids is still running
after SIGKILL, the function will return 0.

=over 2

=item $pid_ar - An arrayref of pids to terminate

=item $verbose - If true, print information about what is being terminated

=item $wait_time_in_seconds - The number of seconds to wait before sending SIGKILL if a process fails to terminate after SIGTERM

=back

=cut

sub safekill_multipid {
    my ( $pid_ar, $verbose, $wait_time_in_seconds ) = @_;

    return _safekill_multipid( $pid_ar, $verbose, $wait_time_in_seconds );
}

sub safekill {
    my ( $deadcmd, $verbose, $wait_time_in_seconds, $immune_pids_ar, $allowed_owners ) = @_;

    my $txtdeadcmd = ref $deadcmd eq 'ARRAY' ? join( ',', @{$deadcmd} ) : $deadcmd;

    my $immune_pids_hr = _generate_immune_pids_hr_from_ar($immune_pids_ar);

    my @pids = grep { !$immune_pids_hr->{$_} } Cpanel::PsParser::get_pids_by_name( $deadcmd, $allowed_owners );

    if ( !@pids ) {
        print "Waiting for $txtdeadcmd to shutdown ... not running.\n" if $verbose;
        return 0;
    }

    return _safekill_multipid( \@pids, $verbose, $wait_time_in_seconds, $immune_pids_hr, $txtdeadcmd );
}

sub _generate_immune_pids_hr_from_ar {
    my ($immune)    = @_;
    my $mypid       = $$;
    my %immune_pids = map { $_ => 1 } @{ $immune || [] };
    $immune_pids{$mypid} = 1;

    return \%immune_pids;

}

sub _safekill_multipid {
    my ( $pid_ref, $verbose, $wait_time_in_seconds, $immune_hr, $txtdeadcmd ) = @_;

    my @pids = @$pid_ref;

    $wait_time_in_seconds ||= 15;
    $txtdeadcmd           ||= join( ',', @pids );

    print "Waiting for $txtdeadcmd to shutdown ..." if $verbose;

    my $num_killed = _kill_group( 'TERM', @pids );

    if ( !$num_killed ) {
        print " not running.\n" if $verbose;
        return 0;
    }

    my $waited = 0;
    while ( $num_killed && $waited <= $wait_time_in_seconds ) {
        print '.' if $verbose;

        $num_killed = _kill_group( 0, @pids );

        if ( !$num_killed ) {
            print " terminated.\n" if $verbose;
            return 1;
        }

        if ( $waited > 0.5 ) {
            $waited += 0.05;
            Cpanel::TimeHiRes::sleep(0.05);
        }
        elsif ( $waited > 0.01 ) {
            $waited += 0.01;
            Cpanel::TimeHiRes::sleep(0.01);
        }
        else {
            $waited += 0.0025;
            Cpanel::TimeHiRes::sleep(0.0025);
        }

        waitpid( $_, 1 ) for @pids;    # in case its a child of us and in zombie state
    }

    print " terminating $txtdeadcmd ..." if $verbose;

    $num_killed = _kill_group( 'KILL', @pids );

    if ( !$num_killed ) {
        print " terminated.\n" if $verbose;
        return 0;
    }

    while ( $num_killed && ( $waited <= $wait_time_in_seconds * 2 ) ) {
        print '.' if $verbose;
        $num_killed = _kill_group( 0, @pids );
        if ( !$num_killed ) {
            print " terminated.\n" if $verbose;
            return 1;
        }
        Cpanel::TimeHiRes::sleep(0.1);
        $waited += 0.1;
        waitpid( $_, 1 ) for @pids;    # in case its a child of us and in zombie state
    }

    print " failed to kill process.\n" if $verbose;
    return 0;
}

sub _kill_group {
    my ( $signal, @pids ) = @_;

    my $num_killed = 0;

    for my $pid (@pids) {
        if ( kill $signal, $pid ) {
            $num_killed++;
        }
        elsif ($!) {
            warn "kill($signal, $pid): $!" if $! != _ESRCH();
        }
    }

    return $num_killed;
}

=head2 killall($signal, $deadcmd, $verbose, $immune, $allowed_owners_hr)

Like killall from psmisc, this function will send a signal to all processes
that match $deadcmd.

$signal - The signal to send the process.  This can be a number of a named
signal like 'KILL'

$deadcmd - All commands that match this string (or regex) will have the
signal sent to it.

$verbose - If set to a truthy value, output about what is being killed
will be sent to STDOUT

$immune - An array ref of pids to exclude from being sent the signal

$allowed_owners_hr - A hashref or uids or users that are allowed to be
to be matched when matching $deadcmd.

=cut

sub killall {
    my ( $signal, $deadcmd, $verbose, $immune, $allowed_owners_hr ) = @_;
    my $mypid = $$;
    $signal =~ tr/-//d;

    my ( $proc_status, $proc_statusmsg ) = _verify_proc_mounted();

    $signal = $Cpanel::Signal::Numbers::SIGNAL_NUMBER{$signal} if $signal =~ tr{0-9}{}c;

    if ( $signal =~ tr{0-9}{}c || $deadcmd eq "" ) {
        return ( 0, 0, "Usage: killall(signal, command, [verbose, immunte, allowed_owners_hr])" );
    }
    elsif ( $deadcmd eq "init" ) {
        die "PANIC! Attempted to kill init!\n";
    }

    my %immune_pids = map { $_ => 1 } @{ $immune || [] };
    $immune_pids{$mypid} = 1;
    my @pids = grep { !$immune_pids{$_} } Cpanel::PsParser::get_pids_by_name( $deadcmd, $allowed_owners_hr );

    my @killed_pids;

    for my $pid (@pids) {
        if ( kill $signal, $pid ) {
            push @killed_pids, $pid;
        }
        else {
            warn "kill($signal, $pid): $!";
        }
    }

    my $pretty_proc_names = ref $deadcmd eq 'ARRAY' ? join( ',', @{$deadcmd} ) : $deadcmd;

    my $killed_str   = @killed_pids ? "@killed_pids: " : q<>;
    my $procs_killed = 0 + @killed_pids;

    return ( 1, $procs_killed, "$procs_killed process" . ( $procs_killed > 1 || $procs_killed == 0 ? "es" : '' ) . " ($killed_str" . $pretty_proc_names . ") sent signal $signal" );
}

1;
