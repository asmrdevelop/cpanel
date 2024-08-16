package Cpanel::Async::Flock;

# cpanel - Cpanel/Async/Flock.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::Flock

=head1 SYNOPSIS

    # Reject the promise after 30s w/ a timeout error if there’s no lock:
    my $flock_p = Cpanel::Async::Flock::flock( $fh, '/path/to/file', 30 );

=head1 DESCRIPTION

(NB: Are you sure you don’t want L<Cpanel::Async::FlockFile> instead?)

This module implements a promise interface around L<flock(2)>.

This module assumes use of L<AnyEvent>.

=head1 CAVEATS

The same issues that attend any use of L<flock(2)> apply here. In particular,
avoid use of this module in any context where NFS might come into play.

See L<Cpanel::UserMutex::Privileged> for a technique that can solve that
problem. (For unprivileged code you could make an admin call that creates the
lock then passes it back to the caller.)

=head1 SEE ALSO

L<Cpanel::Async::FlockFile> wraps this module with useful filesystem logic.
In fact, this module may I<only> be directly useful for converting an
existing lock, i.e., shared <-> exclusive.

=cut

#----------------------------------------------------------------------

use AnyEvent    ();
use Promise::XS ();

use Cpanel::Exception        ();
use Cpanel::FileUtils::Flock ();

# exposed for testing
our $_POLL_INTERVAL = 1;

use constant _DEBUG => 0;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise() = flock_EX( $FILEHANDLE, $PATH [, $TIMEOUT] )

Tries to exclusive-lock $FILEHANDLE until $TIMEOUT passes.
If $TIMEOUT is falsy or not given, this times out right away if the
initial attempt indicates unavailability of the lock.

B<IMPORTANT:> This requires that $FILEHANDLE and $PATH reliably
refer to the same filesystem node. If they’re not, the promise
rejects with an appropriate error.

=cut

sub flock_EX {
    return _flock( 'EX', @_ );
}

=head2 promise() = flock_SH( $FILEHANDLE, $PATH [, $TIMEOUT] )

Like C<flock_EX()> but tries for a shared lock instead of an
exclusive lock.

=cut

sub flock_SH {
    return _flock( 'SH', @_ );
}

sub _flock ( $lock_type, $fh, $lockpath, $timeout = undef ) {
    my $promise;

    if ( _try_lock( $lock_type, $fh ) ) {
        _DEBUG && print STDERR "Lock ($lockpath) succeeded on 1st try!\n";

        $promise = Promise::XS::resolved();
    }
    elsif ($timeout) {
        _DEBUG && print STDERR "Lock ($lockpath) is busy; timeout in $timeout seconds …\n";

        $promise = _lock_promise( $lock_type, $fh, $lockpath, $timeout );
    }
    else {
        _DEBUG && print STDERR "Lock ($lockpath) is busy; timing out immediately …\n";

        $promise = Promise::XS::rejected( _get_timeout_err($lockpath) );
    }

    return $promise;
}

sub _try_lock ( $lock_type, $fh ) {
    _DEBUG && print STDERR "trying lock …\n";

    return Cpanel::FileUtils::Flock::flock( $fh, $lock_type, 'NB' );
}

sub _get_timeout_err ( $lockpath, $timeout = undef ) {
    my $msg;

    if ($timeout) {
        $msg = "Lock unavailable for $timeout seconds: $lockpath";
    }
    else {
        $msg = "Lock unavailable: $lockpath";
    }

    return Cpanel::Exception::create_raw( 'Timeout', $msg );
}

sub _lock_promise ( $lock_type, $fh, $lockpath, $timeout ) {

    # Start up an inotify that listens for close events; each time such
    # an event arrives, try to lock the file. Also check every so often
    # “just in case”. Time out after the given $timeout has passed.

    my $d = Promise::XS::deferred();

    my $inotify = _create_inotify($lockpath);

    if ( eval { _verify_sameness( $fh, $lockpath ); 1 } ) {
        my $ae_watch;
        my $timer;

        my $clear_stuff_cr = sub {
            undef $ae_watch;
            undef $timer;
            undef $inotify;
        };

        my $check_lock_cr = sub {
            if ( _try_lock( $lock_type, $fh ) ) {
                _DEBUG && print STDERR "got lock\n";

                $clear_stuff_cr->();
                $d->resolve();

                return 1;
            }

            _DEBUG && print STDERR "lock still busy\n";
        };

        $ae_watch = AnyEvent->io(
            fh   => $inotify->fileno(),
            poll => 'r',
            cb   => sub {
                _DEBUG && print STDERR "lock ($lockpath) inotify\n";

                () = $inotify->poll();    # we don’t care about the event(s)
                $check_lock_cr->();
            },
        );

        my $end_time = time + $timeout;

        $timer = AnyEvent->timer(

            # Check every $_POLL_INTERVAL seconds.
            interval => $_POLL_INTERVAL,

            # Check right away in case the lock disappeared before the
            # inotify was created.
            after => 0,

            cb => sub {
                _DEBUG && print STDERR "lock ($lockpath) interval\n";

                $check_lock_cr->() or do {
                    if ( time > $end_time ) {
                        $clear_stuff_cr->();
                        $d->reject( _get_timeout_err( $lockpath, $timeout ) );
                    }
                };
            },
        );
    }
    else {
        $d->reject($@);
    }

    return $d->promise();
}

sub _create_inotify ($lockpath) {

    # It’d be nice to use fanotify, which can work with file descriptors
    # rather than paths, instead of inotify, but fanotify won’t work with
    # CloudLinux 6, and for now the maintenance effort to support both
    # outweighs the benefits.

    local ( $@, $! );
    require Cpanel::Inotify;

    my $inotify = Cpanel::Inotify->new( flags => ['NONBLOCK'] );
    $inotify->add( $lockpath, flags => ['CLOSE'] );

    return $inotify;
}

sub _verify_sameness ( $fh, $lockpath ) {
    my @pathstat = stat $lockpath or do {
        die "stat($lockpath): $!\n";
    };

    my @fhstat = stat $fh or do {
        my $fd = fileno $fh;
        die "stat FD $fd: $!\n";
    };

    if ( "@pathstat[0,1]" ne "@fhstat[0,1]" ) {
        my $fd = fileno $fh;

        # We could try to tolerate this by re-open()ing,
        # but for now let’s just keep it simple and give up.
        die "$lockpath doesn’t match given FD ($fd)!\n";
    }

    return;
}

1;
