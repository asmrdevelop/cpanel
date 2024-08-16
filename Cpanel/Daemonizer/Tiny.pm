package Cpanel::Daemonizer::Tiny;

# cpanel - Cpanel/Daemonizer/Tiny.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Daemonizer::Tiny

=head1 SYNOPSIS

    my $daemon_pid = Cpanel::Daemonizer::Tiny::run_as_daemon( sub { … } );

=head1 DISCUSSION

This module implements a “classic” double-fork daemonize. Along the way
it sets rlimits to their maximum. Discussions of this
technique are easy to find out and about. One thing that this does a bit
differently, though, is that it passes back the daemon’s PID to the caller.
This may or may not be useful, depending on whether the daemonize logic does
its own C<fork()>--but that’s something the caller will need to determine.

=cut

use strict;
use Cpanel::CloseFDs          ();
use Cpanel::Exception         ();
use Cpanel::FHUtils::Blocking ();
use Cpanel::FHUtils::Tiny     ();
use Cpanel::ForkAsync         ();
use Cpanel::Rlimit            ();
use Cpanel::Syscall           ();
use Cpanel::Wait::Constants   ();
use IO::CloseFDs              ();    # Required for Cpanel::CloseFDs

my $WAIT_TIME = 30;

#for testing
our $_TODO_AFTER_FORK;

=head1 FUNCTIONS

=head2 C<run_as_daemon(CODE, ARGS...)>

Runs the code passing the args list in a daemonized process.

=head3 ARGUMENTS

=over

=item CODE

Code reference to run in the daemon process.

=item ARGS...

List of arguments to pass the the code when calling it.

B<Example>

CODE(ARG1, ARG2, ..., ARGN);

=back

=head3 RETURNS

The pid of the daemon process.

=cut

sub run_as_daemon {
    my ( $coderef, @args ) = @_;
    return run_as_daemon_with_options( {}, $coderef, @args );
}

=head2 C<run_as_daemon_with_options(OPTS, CODE, ARGS...)>

Runs the code with the args listed in a daemonized process. This method
also allows you to pass in certain additional options that modify the way
the deamon process starts.

=head3 ARGUMENTS

=over

=item OPTS

Optional HASHREF with the following options:

=over

=item excludes

Optional ARRAYREF where each element is a file handle or fileno. When passed, each
file handle or fileno is left opened in the child process allowing that application
code to choose when to close them.

See L<Cpanel::CloseFDs::fast_daemonclosefds> for more information on these excludes.

=back

=item CODE

Code reference to run in the daemon process.

=item ARGS...

List of arguments to pass the code when calling it.

B<Example>

CODE(ARG1, ARG2, ..., ARGN);

=back

=head3 RETURNS

The pid of the daemon process.

=cut

sub run_as_daemon_with_options {
    my ( $opts, $coderef, @args ) = @_;
    $opts = {} if !$opts;

    local ( $!, $^E );

    pipe my ( $pr, $cw ) or die "pipe() failed: $!";

    #The PID of the immediate child isn’t of much interest
    #outside this scope. What the caller would care about would be
    #the “grandchild” PID. (Right??)
    my $child_pid = Cpanel::ForkAsync::do_in_child(
        sub {
            close $pr or die Cpanel::Exception::create( 'IO::CloseError', [ error => $! ] );

            $_TODO_AFTER_FORK->() if $_TODO_AFTER_FORK;

            Cpanel::Syscall::syscall('setsid');

            my $pid = Cpanel::ForkAsync::do_in_child(
                sub {
                    chdir('/') or die Cpanel::Exception::create( 'IO::ChdirError', [ path => '/', error => $! ] );
                    Cpanel::CloseFDs::fast_daemonclosefds( except => $opts->{excludes} );
                    Cpanel::Rlimit::set_rlimit_to_infinity();
                    $coderef->(@args);
                    exit;
                },
            );

            print {$cw} pack 'L', $pid or die Cpanel::Exception::create( 'IO::WriteError', [ error => $! ] );

            close $cw or die Cpanel::Exception::create( 'IO::CloseError', [ error => $! ] );

            exit;
        },
    );

    close $cw or die Cpanel::Exception::create( 'IO::CloseError', [ error => $! ] );

    #Just to be sure that a catastrophic, premature end to the grandchild
    #process doesn’t lock this process, we loop continuously. What we EXPECT
    #to happen is that $grandchild_pid will be populated with the bytes that
    #the child process writes to $cw. Of course, that process could fail,
    #which we ourselves should indicate with a die(). We check for that fate
    #on each loop iteration as well as the expected outcome.

    #To make this happen we first set $pr to be non-blocking:
    Cpanel::FHUtils::Blocking::set_non_blocking($pr);

    my $rout;
    my $rin            = Cpanel::FHUtils::Tiny::to_bitmask($pr);
    my $start          = time;
    my $grandchild_pid = q<>;
    my $length_L       = length pack 'L', 0;
    my $reaped;

    while ( time < $WAIT_TIME + $start ) {
        if ( -1 == select $rout = $rin, undef, undef, undef ) {
            if ( !$!{'EINTR'} && !$!{'EAGAIN'} ) {
                die Cpanel::Exception::create( 'IO::SelectError', [ error => $! ] );
            }
        }
        elsif ( $rout & $rin ) {
            if ( sysread( $pr, $grandchild_pid, $length_L, length $grandchild_pid ) ) {
                last if length($grandchild_pid) == $length_L;
            }

            if ( $! && !$!{'EINTR'} && !$!{'EAGAIN'} ) {
                die Cpanel::Exception::create( 'IO::ReadError', [ error => $! ] );
            }
        }

        if ( _waitpid_or_die( $child_pid, $Cpanel::Wait::Constants::WNOHANG ) ) {
            $reaped = 1;
            last;
        }
    }

    close $pr or die Cpanel::Exception::create( 'IO::CloseError', [ error => $! ] );

    if ( !$reaped ) {
        _waitpid_or_die( $child_pid, 0 );
    }

    return unpack 'L', $grandchild_pid;
}

sub _waitpid_or_die {
    my ( $child_pid, $mode ) = @_;

    local $?;
    my $ret = waitpid $child_pid, $mode;
    if ($ret) {
        if ($?) {
            if ( $? & 0xff ) {
                die Cpanel::Exception::create( 'ProcessFailed::Signal', [ pid => $child_pid, signal_code => $? & 0xff ] );
            }
            else {
                die Cpanel::Exception::create( 'ProcessFailed::Error', [ pid => $child_pid, error_code => $? >> 8 ] );
            }
        }
    }

    return $ret;
}

1;
