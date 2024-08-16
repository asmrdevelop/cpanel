package Cpanel::Async::Forker;

# cpanel - Cpanel/Async/Forker.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::Forker - Run a subroutine in a forked process.

=head1 SYNOPSIS

    use AnyEvent;

    my $forker = Cpanel::Async::Forker->new();

    my $p = $forker->do_in_child( sub { print "hi\n" } );

    my $cv = AnyEvent->condvar();

    $p->then( sub { print "subprocess is done\n" } )->finally($cv);

    $cv->recv();

=head1 BEFORE USING THIS MODULE

This module is a “crutch” to achieve non-blocking I/O as a shim around
the blocking I/O in modules like L<Cpanel::RemoteAPI>. The overhead that
forking entails makes this unideal in terms of performance, but it’s a
useful expedient in lieu of rewriting a tool—let alone an entire
framework—to use non-blocking I/O.

A more “legitimate” use for this module would be to run a
computationally-intensive task in its own process in order to avoid
blocking other tasks. Anything computationally-intensive, though, is
likely better done in XS anyway.

=head1 DESCRIPTION

This module runs a Perl subroutine in a subprocess and makes that
subroutine’s return available to the caller.

=head1 WHEN TO USE THIS MODULE (OR SOMETHING ELSE)

L<Cpanel::ForkSync> and L<Cpanel::Parallelizer> block, so if you need
non-blocking I/O they won’t do.

L<Mojo::IOLoop::Subprocess>, L<IO::Async::Function>, and L<AnyEvent::Util>
all provide non-blocking implementations but entail a certain commitment to
their respective event interface and may be problematic in terms of size.

This module exists, then, to do the needed work lightly, favoring
modules that a cPanel & WHM Perl process may likely already have loaded.
It uses L<AnyEvent> for now but is simple enough that it could, if needs
dictate, easily use a different event framework, e.g., L<IO::Async>.

=cut

#----------------------------------------------------------------------

use AnyEvent     ();
use IO::SigGuard ();
use Promise::XS  ();

# Sereal may be a better choice, but C::AB::S has been battle-tested in
# cPanel & WHM for many years.
use Cpanel::AdminBin::Serializer ();

use Cpanel::Autodie          qw( sysread_sigguard syswrite_sigguard );
use Cpanel::Async::Throttler ();
use Cpanel::ForkAsync        ();

our $_WARN_ON_KILL = 0;

my $_DEFAULT_PROCESS_LIMIT = 10;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class.

%OPTS are:

=over

=item * C<process_limit> - The maximum number of forked processes that the
object will create at a given time. Any tasks submitted when this many
forked processes are already in play will be deferred to a wait queue,
à la L<Cpanel::Async::Throttler>.

Defaults to 10.

=back

=cut

sub new ( $class, %opts ) {
    my $process_limit = delete $opts{'process_limit'} || $_DEFAULT_PROCESS_LIMIT;

    if (%opts) {
        my @unknown = sort keys %opts;
        die "$class: Unknown parameters: [@unknown]";
    }

    my $throttler = Cpanel::Async::Throttler->new($process_limit);

    my %self = (
        _throttler    => $throttler,
        _pid          => $$,
        _pid_deferred => {},
        _pid_status   => {},
    );

    return bless \%self, $class;
}

=head2 $promise = I<OBJ>->do_in_child( $CODEREF )

Executes $CODEREF, in scalar context, in a subprocess, subject to I<OBJ>’s
configuration constraints. (cf. C<new()>)

Returns a promise that resolves with $CODEREF’s return value.

$CODEREF’s return value B<MUST> fit L<Cpanel::AdminBin::Serializer>’s
data model and B<MUST NOT> include any C<bless()>ed references.

=head3 Fault tolerance

It would be ideal to implement this such that, if the last reference to the
promise goes away, the parent process forcibly kills the subprocess.
Unfortunately, in order for the parent’s I/O listener to be able to resolve
the promise, that listener itself has to hold a reference to the promise,
which means the last reference to the promise doesn’t go away until that
I/O listener is finished. But the I/O listener doesn’t finish until the
child process does, which means the parent can’t force-kill the child
process until that same child process finishes.

The current solution is to require callers to retain a reference to
I<OBJ> as long as any promises are pending; if the last reference to
I<OBJ> goes away, any pending promises are forcibly terminated. It may
be possible to use weakened references or some other technique to achieve
the optimal workflow, but this is where we are for now.

=cut

sub do_in_child ( $self, $cr ) {
    return $self->{'_throttler'}->add(
        sub {
            $self->_do_now_in_child($cr);
        }
    );
}

sub _do_now_in_child ( $self, $cr ) {
    my $deferred = Promise::XS::deferred();

    pipe( my $r, my $w ) or die "pipe() failed: $!";

    my $output_serialized = q<>;

    my $pid = Cpanel::ForkAsync::do_in_child(
        sub {
            close $r;

            my $ret;

            my $to_freeze;

            if ( eval { $ret = $cr->(); 1 } ) {
                $to_freeze = [ 1, $ret ];
            }
            else {

                # Stringify the exception because that’s probably what we need.
                # It might eventually be nice to have a way to serialize the
                # exception objects, but this works for now.
                $to_freeze = [ 0, "$@" ];
            }

            my $serialized = eval { Cpanel::AdminBin::Serializer::Dump($to_freeze) } || do {
                my $type = $to_freeze->[0] ? 'success' : 'failure';

                $to_freeze = [ 0, "Failed to serialize $type response ($to_freeze->[1]): $@" ];
                Cpanel::AdminBin::Serializer::Dump($to_freeze);
            };

            IO::SigGuard::syswrite( $w, $serialized ) or warn( __PACKAGE__ . ": write from process $$: $!" );

            close $w;
        }
    );

    close $w;

    my $pids_hr = $self->{'_pid_deferred'};
    $pids_hr->{$pid} = $deferred;

    my $pid_status_hr = $self->{'_pid_status'};

    my ( $iowatch, $childwatch );

    AnyEvent->now_update();

    my $sub_callback = sub () {

        # No-op if the pipe is still open.
        return if fileno $r;

        my $child_err = delete $pid_status_hr->{$pid};

        # No-op if the subprocess isn’t reaped.
        return if !defined $child_err;

        my $deferred = delete $pids_hr->{$pid};

        # No-op if DESTROY already murdered the child.
        return if !$deferred;

        if ($child_err) {
            require Cpanel::ChildErrorStringifier;

            # Right now there’s no PID in here. It’d be nice to improve that.
            my $err = Cpanel::ChildErrorStringifier->new($child_err)->to_exception();

            $deferred->reject($err);
        }
        else {
            _handle_zero_exit( $pid, \$output_serialized, $deferred );
        }

        return;
    };

    $childwatch = AnyEvent->child(
        pid => $pid,
        cb  => sub ( $pid, $status ) {
            undef $childwatch;
            $pid_status_hr->{$pid} = $status;

            $sub_callback->();

            return;
        },
    );

    $iowatch = AnyEvent->io(
        fh   => $r,
        poll => 'r',
        cb   => sub {
            my $got = eval { Cpanel::Autodie::sysread_sigguard( $r, $output_serialized, 65536, length $output_serialized ) };

            if ( !$got ) {
                warn if !defined $got;

                undef $iowatch;

                close $r;

                $sub_callback->();
            }
        },
    );

    return $deferred->promise();
}

sub _handle_zero_exit ( $pid, $output_serialized_s, $deferred ) {
    my $parse = eval { Cpanel::AdminBin::Serializer::Load($$output_serialized_s) } or do {
        my $msg = "Failed to parse serialized response from process $pid: $@";

        $deferred->reject($msg);
        return;
    };

    my ( $ok, $detail ) = @$parse;

    if ($ok) {
        $deferred->resolve($detail);
    }
    else {
        $deferred->reject($detail);
    }

    return;
}

sub DESTROY ($self) {
    return if $$ != $self->{'_pid'};

    for my $pid ( keys %{ $self->{'_pid_deferred'} } ) {
        my $deferred = delete $self->{'_pid_deferred'}{$pid};

        my $ref = ref $self;

        my $msg = "Process $pid outlived its parent $ref object. Killing process …";
        $deferred->reject($msg);

        require Cpanel::Kill::Single;
        Cpanel::Kill::Single::safekill_single_pid($pid);
    }

    return;
}

1;
