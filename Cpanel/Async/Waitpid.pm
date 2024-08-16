package Cpanel::Async::Waitpid;

# cpanel - Cpanel/Async/Waitpid.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::Waitpid

=head1 SYNOPSIS

    Cpanel::Async::Waitpid::timed($pid)->then(
        sub ($CHILD_ERROR) { .. },
        sub ($err) { .. },
    );

=head1 DESCRIPTION

This module implements a “timed” waitpid. See below.

=cut

#----------------------------------------------------------------------

use Carp        ();
use AnyEvent    ();
use Promise::XS ();

use constant {

    # The time before we give up and start signaling:
    _DEFAULT_TIMEOUT => 60,

    # The time before we switch from SIGTERM to SIGKILL:
    _DEFAULT_GRACE1 => 15,

    # The time before we give up on SIGKILL:
    _DEFAULT_GRACE2 => 15,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 promise($CHILD_ERROR) = Cpanel::Async::Waitpid::timed( $PID, %OPTS )

Returns a promise whose resolution is the $PID’s final wait state
(i.e., C<$CHILD_ERROR>, or C<$?>).

Ordinarily you should only call this once you’re done interacting with
a process and expect it to end “soon”. In the event of processes that
don’t behave as we expect, though, this implements some useful timeouts.
Thus, our returned promise will I<always> resolve or reject, never hang.

The workflow is thus:

=over

=item * Wait for the initial timeout to pass. (Ordinarily your subprocess will
end within this period.)

=item * Send SIGTERM, and warn about it.

=item * Once a grace period passes, if that process is still around,
send SIGKILL, and warn about that.

=item * Once another grace period passes, give up, and reject the promise
with an error message. This should be quite rare, restricted to processes
that (for whatever reason) don’t terminate in response to SIGKILL.

=back

%OPTS control the timeout behavior:

=over

=item * C<timeout> - The initial timeout period, in seconds.
Defaults to 60s.

=item * C<grace1> - The grace period between SIGTERM and SIGKILL,
in seconds. Defaults to 15s.

=item * C<grace2> - The grace period between SIGKILL and give-up,
in seconds. Defaults to 15s.

=back

The returned promise will reject if $PID is not a child process or if
we fail to signal the child process. (Or, as mentioned above, if SIGKILL
doesn’t terminate the process.)

This will also throw (“loudly”) if the inputs are “obviously” invalid,
e.g., unrecognized %OPTS or invalid $PID.

=cut

sub timed ( $pid, %opts ) {

    # AnyEvent expects $SIG{'CHLD'} to be falsy and doesn’t care that
    # 'DEFAULT' means the same behavior. So let’s quietly help it along.
    undef $SIG{'CHLD'} if $SIG{'CHLD'} && $SIG{'CHLD'} eq 'DEFAULT';

    # confess()ions should only happen from programmer error.

    Carp::confess("Give a real PID, not $pid!") if $pid <= 0;

    my ( $timeout, $grace1, $grace2 ) = delete @opts{ 'timeout', 'grace1', 'grace2' };

    if (%opts) {
        my @keys = sort keys %opts;
        Carp::confess("Bad opt(s): @keys");
    }

    $timeout ||= _DEFAULT_TIMEOUT;
    $grace1  ||= _DEFAULT_GRACE1;
    $grace2  ||= _DEFAULT_GRACE2;

    my $d = Promise::XS::deferred();

    local ( $!, $? );
    my $reaped_pid         = waitpid( $pid, 1 );
    my $reaped_child_error = $?;

    my ( $pid_watch, $timer, $settled );

    $pid_watch = AnyEvent->child(
        pid => $pid,
        cb  => sub ( $, $childerr, @ ) {
            $settled = 1;
            $d->resolve($childerr);
        },
    );

    my $softsig = 'TERM';
    my $killsig = 'KILL';

    if ( -1 == $reaped_pid ) {

        # -1 means “no such child process”. It’s possible that waitpid()
        # gave that response, though, because AnyEvent “pre-reaped” $pid
        # for us. To accommodate that we defer for a loop iteration to
        # ensure that AnyEvent has time to call $pid_watch’s callback
        # if it did indeed “pre-reap”.

        AnyEvent::postpone(
            sub {
                if ( !$settled ) {

                    # OK, AnyEvent didn’t reap, which means $pid isn’t a
                    # child process. So now we error out.
                    $d->reject("This process ($$) does not have a child process with PID $pid.");
                }
            }
        );
    }
    elsif ($reaped_pid) {

        # Oh hey! We got here because our process was already ready to
        # reap. So there’s nothing to do, and we can just resolve the
        # promise.
        $d->resolve($reaped_child_error);
    }
    else {
        $timer = AnyEvent->timer(
            after => $timeout,
            cb    => sub {
                my $elapsed = $timeout;

                warn "Process $pid did not end within ${elapsed}s; sending SIG$softsig …\n";

                kill $softsig, $pid or do {
                    $d->reject("kill($softsig, $pid): $!");
                    return;
                };

                $timer = AnyEvent->timer(
                    after => $grace1,
                    cb    => sub {
                        $elapsed += $grace1;

                        warn "Process $pid did not end within ${elapsed}s; sending SIG$killsig …\n";

                        kill 'KILL', $pid or do {
                            $d->reject("kill(KILL, $pid): $!");
                            return;
                        };

                        $timer = AnyEvent->timer(
                            after => $grace2,
                            cb    => sub {
                                $elapsed += $grace2;

                                $d->reject("Failed to terminate process $pid after ${elapsed}s! Giving up.");
                            },
                        );
                    },
                );
            },
        );
    }

    return $d->promise()->finally(
        sub {
            undef $pid_watch;
            undef $timer;
        }
    );
}

1;
