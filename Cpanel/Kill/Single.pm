package Cpanel::Kill::Single;

# cpanel - Cpanel/Kill/Single.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Kill::Single

=head1 SYNOPSIS

    Cpanel::Kill::Single::safekill_single_pid( '12345' );

=head1 DESCRIPTION

Logic for ending a process.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::TimeHiRes       ();
use Cpanel::Wait::Constants ();
use Cpanel::Debug           ();

our $SAFEKILL_TIMEOUT = 10;      # in seconds;
our $SIG_KILL_TIMEOUT = 15;      # in seconds;
our $SLEEP_INTERVAL   = 0.05;    # in seconds, must be less then 1 second

our $INITIAL_SAFEKILL_SIGNAL = 'TERM';
our $KILL_SIGNAL_NAME        = 'KILL';    # for tests

=head2 $child_error = safekill_single_pid( PID, OPTIONAL_TIMEOUT )

Synchronously end the process with the given C<PID>:

=over

=item * First, send C<SIGTERM>.

=item * Poll periodically for the end of that process, up to
a preset timeout. (If C<OPTIONAL_TIMEOUT> is not given, the default
is 10 seconds.)

=item * If the process does not end before the timeout, send C<SIGKILL>.

=back

The return value is what would be set in C<$?> from C<waitpid>.
(Global C<$?> itself is not set here.) Note that in rare cases,
the return might actually be undef. (See the code for details.)

B<NOTE:> It would be nice to use C<signalfd> for this if it could
be made to work.

=cut

#This does not set $?, but it returns the value that would normally be in $?
#after reaping a child process.
#
sub safekill_single_pid {
    my ( $pid, $timeout ) = @_;
    my $kill = kill $INITIAL_SAFEKILL_SIGNAL, $pid;
    if ( $kill <= 0 ) {
        Cpanel::Debug::log_warn("safekill_single_pid failed to send TERM to pid: $pid: $!");
    }

    $timeout ||= $SAFEKILL_TIMEOUT;
    my $start     = Cpanel::TimeHiRes::time();
    my $end       = $start + $timeout;
    my $wait_time = 0.025;
    my $ret;

    local $?;

    while ( Cpanel::TimeHiRes::time() < $end ) {

        $kill = kill( 0, $pid );

        # in case it’s a child of us and in zombie state
        my $dead = waitpid( $pid, $Cpanel::Wait::Constants::WNOHANG );
        $ret = $? if $dead && !defined $ret && $? != -1;

        #If we weren’t able to send “SIGZERO” to $pid -- i.e.,
        #if the process isn’t one we can reach:
        if ( $kill <= 0 ) {

            #If the process wasn’t signalable but *did* indicate
            #to waitpid() that it’s not dead, then we’ll just loop again.
            #(Can that ever happen?)
            #
            #But, assuming that the process responds normally to SIGTERM,
            #we’ll return here.
            return $ret if $dead;
        }

        #After the first check, wait 1/40th of a second;
        #thereafter, until 1 second after we started, wait 1/20th of a second.
        elsif ( Cpanel::TimeHiRes::time() < $start + 1 ) {
            Cpanel::TimeHiRes::sleep($wait_time) if $dead < 1;
            $wait_time = $SLEEP_INTERVAL;
        }

        #After 1 second after start, wait a full second between checks.
        else {
            Cpanel::TimeHiRes::sleep(1) if $dead < 1;
        }
    }

    #We got here because, after $timeout seconds,
    #the process still didn’t go away. So, the nuclear option:
    kill $KILL_SIGNAL_NAME, $pid;

    # It possible for the process to get stuck in a 'D' state so
    # we give up after $SIG_KILL_TIMEOUT
    for ( 1 .. ( $SIG_KILL_TIMEOUT / $SLEEP_INTERVAL ) ) {
        my $dead = waitpid( $pid, $Cpanel::Wait::Constants::WNOHANG );    # in case it’s a child of us and in zombie state
                                                                          #Would $ret ever be undef after here, then?
        $ret = $? if $dead && !defined $ret && $? != -1;
        return $ret if $dead;
        Cpanel::TimeHiRes::sleep($SLEEP_INTERVAL);
    }

    return $ret;
}

# 10 second cleanup time is the default
sub safekill_single_pid_background {
    my ( $pid, $timeout ) = @_;

    require Cpanel::ForkAsync;
    my $reaper_pid = Cpanel::ForkAsync::do_in_child(
        sub {
            my $ret = safekill_single_pid( $pid, $timeout );
            exit( $ret >> 8 );
        }
    );

    return $reaper_pid;
}

1;
