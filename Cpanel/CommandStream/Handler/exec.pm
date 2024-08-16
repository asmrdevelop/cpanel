package Cpanel::CommandStream::Handler::exec;

# cpanel - Cpanel/CommandStream/Handler/exec.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Handler::exec

=head1 DESCRIPTION

This class implements handler logic for C<exec> CommandStream requests.

This class extends L<Cpanel::CommandStream::Handler>.

=head1 WORKFLOW

=over

=item * The request contains a C<command>, which is an array (i.e., a Perl
array I<reference>) of the program name and any arguments.

=item * If the command executes successfully, an C<exec_ok> message is sent.
This message contains a C<pid>.

=item * 1 or more C<stdout> and C<stderr> messages follow, each of which
contains a C<chunk>. When C<chunk> is empty, this indicates the end of that
output stream.

=item * Once the command finishes, C<ended> is sent. This message contains
a C<status>, which is the same value as Perl’s C<$?>. This message
will B<never> arrive before both C<stdout> and C<stderr> are finished.

=back

=head1 FAILURES

C<bad_arguments> contains a C<why> that explains why the given
arguments don’t work.

All other responses will contain an C<errno> and C<text> that indicate
the failure. They’re not listed here because they’re pretty obvious
when they happen. (C<exec_failed>, for instance)

Note that C<stdout_failed> and C<stderr_failed> merely indicate
failures to read from a pipe and, depending on the application, may not
need to be considered fatal.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::CommandStream::Handler',
);

use AnyEvent     ();
use IO::SigGuard qw(sysread send);
use Promise::XS  ();

use Cpanel::Exec              ();
use Cpanel::Finally           ();
use Cpanel::FHUtils::Blocking ();
use Cpanel::FHUtils::FDFlags  ();
use Cpanel::Socket::Constants ();
use Cpanel::Try               ();

use constant {
    _READ_SIZE => 131072,
    _DEBUG     => 0,
};

#----------------------------------------------------------------------

sub _run ( $self, $req_hr, $courier, $completion_d ) {    ## no critic qw(ManyArgs) - mis-parse
    my $complete_finally = Cpanel::Finally->new(
        sub {
            $completion_d->resolve();
        }
    );

    my $cmd_ar = $req_hr->{'command'} or do {
        _fail_bad_arguments( $courier, "No “command” in request." );
        return;
    };

    if ( 'ARRAY' ne ref $cmd_ar ) {
        _fail_bad_arguments( $courier, "“command” must be an array." );
        return;
    }

    if ( !length $cmd_ar->[0] ) {
        _fail_bad_arguments( $courier, '“command” lacks a program to run.' );
        return;
    }

    _DEBUG() && print STDERR "COMMAND: @$cmd_ar\n";

    my $gave_stdin = length $req_hr->{'stdin'};

    my ( $cpid, $inout, $rerr, $rstatus, $r_end ) = _create_exec_subprocess( $courier, $gave_stdin, @$cmd_ar );
    return if !$cpid;

    $courier->send_response( 'exec_ok', { pid => $cpid } );

    my %label_fh = (
        stdout => $inout,
        stderr => $rerr,
    );

    my %label_deferred = map { $_ => Promise::XS::deferred() } keys %label_fh;

    my @watchers_sr;

    for my $label ( keys %label_fh ) {
        my $fh       = $label_fh{$label};
        my $deferred = $label_deferred{$label};

        push @watchers_sr, _create_read_watcher_sr(
            $courier,
            $label,
            $fh,
            $deferred,
        );
    }

    my $child_end_w;
    push @watchers_sr, \$child_end_w;

    my @io_promises = map { $_->promise() } values %label_deferred;

    if ($gave_stdin) {
        push @io_promises, _create_write_promise( $courier, \$req_hr->{'stdin'}, $inout );
    }

    $child_end_w = AnyEvent->io(
        fh   => $r_end,
        poll => 'r',
        cb   => sub {

            # XXX IMPORTANT XXX
            #
            # Avoid hard references to $self in this callback, or else we
            # have circular references, which might make
            # Cpanel::Destruct::DestroyDetector complain. (The complaints
            # are a good thing! Circular references aren’t.)

            undef $child_end_w;
            close $r_end;

            # The wait should be very short since we know the
            # subprocess has ended.
            local $?;
            waitpid $cpid, 0;

            my $status = $?;

            _DEBUG() && print STDERR "reaped PID $cpid - handler\n";

            # We don’t want to trigger process-ended logic until we’re done
            # reading the process’s outputs.
            Promise::XS::all(@io_promises)->then(
                sub {
                    _DEBUG() && print STDERR "reaped PID $cpid - I/O done\n";

                    $courier->send_response( 'ended', { status => $status } );

                    undef $complete_finally;
                }
            );
        },
    );

    $self->{'_cpid'}          = $cpid;
    $self->{'_child_end_rfh'} = $r_end;
    $self->{'_watchers'}      = \@watchers_sr;

    return;
}

#----------------------------------------------------------------------

# When this object goes away, ensure that we kill its subprocess
# if it’s still alive.
sub DESTROY ($self) {
    if ( $self->{'_watchers'} ) {
        $$_ = undef for @{ $self->{'_watchers'} };

        if ( $self->_subprocess_is_alive() ) {
            require Cpanel::Kill::Single;
            Cpanel::Kill::Single::safekill_single_pid( $self->{'_cpid'} );
        }
    }

    $self->SUPER::DESTROY();

    return;
}

# Potentially useful independently?
sub _create_write_promise ( $courier, $stdin_sr, $write_fh ) {
    my $index = 0;

    my $write_watch;

    my $d = Promise::XS::deferred();

    # We need to send $$stdin_sr to $write_fh, but we also need to
    # accommodate backpressure. When backpressure happens we need
    # to listen for the socket’s writability and then rewrite once
    # that happens. Repeat if we still haven’t written the full buffer.
    # Continue this until we’ve written the whole buffer.
    #
    # Immediately-executed callbacks look funny in Perl, but it’s used
    # here because the logic to continue writing is the same
    # as for our initial write.
    #
    sub {

        # We need send() so that we can avoid SIGPIPE. AnyEvent turns
        # off SIGPIPE anyway, but let’s avoid dependence on that.
        my $wrote = IO::SigGuard::send(
            $write_fh,
            substr( $$stdin_sr, $index ),
            $Cpanel::Socket::Constants::MSG_NOSIGNAL,
        );

        if ($wrote) {
            $index += $wrote;

            if ( $index < length $$stdin_sr ) {

                # An incomplete write means we’ve filled the write buffer,
                # which means we need to poll for writability so we can
                # resume our mission to write all of $$stdin_sr to $write_fh.
                _DEBUG() && print STDERR "creating write watch\n" if !$write_watch;

                $write_watch ||= AnyEvent->io(
                    fh   => $write_fh,
                    poll => 'w',
                    cb   => __SUB__,
                );
            }
            else {
                _DEBUG() && print STDERR "\tDone writing stdin\n";
                $d->resolve();
            }
        }
        else {
            _send_errno_response( $courier, "stdin_failed" );
            $d->resolve();
        }
      }
      ->();

    return $d->promise()->finally(
        sub {
            _DEBUG() && print STDERR "ending write watch\n" if $write_watch;
            undef $write_watch;

            # This really shouldn’t fail …
            shutdown $write_fh, $Cpanel::Socket::Constants::SHUT_WR or do {
                warn "shutdown(SHUT_WR): $!";
            };
        }
    );
}

sub _fail_bad_arguments ( $courier, $why ) {
    $courier->send_response( 'bad_arguments', { why => $why } );

    return;
}

sub _send_errno_response ( $courier, $class ) {
    return $courier->send_response(
        $class,
        {
            errno => 0 + $!,
            text  => "$!",
        },
    );
}

sub _subprocess_is_alive ($self) {
    return defined( fileno $self->{'_child_end_rfh'} );
}

sub _create_read_watcher_sr ( $courier, $label, $fh, $deferred ) {
    my $io_watch;

    $io_watch = AnyEvent->io(
        fh   => $fh,
        poll => 'r',
        cb   => sub {

            # XXX IMPORTANT XXX
            #
            # Avoid hard references to $self in this callback,
            # or else we have circular references.

            warn if !eval {

                my $bytes = IO::SigGuard::sysread( $fh, my $buf, _READ_SIZE );

                if ($bytes) {
                    _DEBUG() && printf STDERR "\t$label: got %s bytes\n", length $buf;

                    my $writeable_promise = $courier->send_response( $label, { chunk => $buf } );

                    if ($writeable_promise) {
                        _DEBUG() && print STDERR "\t$label: backpressure on\n";

                        # We’re here because the transport told us
                        # to stop sending responses until $writeable_promise
                        # resolves.
                        undef $io_watch;

                        my $cur_sub = __SUB__;

                        $writeable_promise->then(
                            sub {
                                _DEBUG() && printf STDERR "\t$label: backpressure off\n";
                                $io_watch = AnyEvent->io(
                                    fh   => $fh,
                                    poll => 'r',
                                    cb   => $cur_sub,
                                );
                            }
                        );
                    }
                }
                else {
                    if ( defined $bytes ) {
                        $courier->send_response( $label, { chunk => q<> } );
                        _DEBUG() && print STDERR "\tEOF $label\n";
                    }
                    else {
                        _send_errno_response( $courier, "${label}_failed" );
                    }

                    undef $io_watch;

                    $deferred->resolve();
                }

                1;
            };
        },
    );

    return \$io_watch;
}

sub _pipe_or_end {
    my ($courier) = @_;    # also $r, $w

    # It’d be nice to have an XS pipe2 implementation so the filehandles
    # could start out non-blocking. (Pure Perl can do it, but it’s slow.)
    pipe( $_[1], $_[2] ) or do {
        _send_errno_response( $courier, 'pipe_failed' );
        return 0;
    };

    Cpanel::FHUtils::Blocking::set_non_blocking($_) for @_[ 1, 2 ];

    return 1;
}

sub _socketpair_or_end {
    my ($courier) = @_;    # also $r, $w

    socketpair( $_[1], $_[2], $Cpanel::Socket::Constants::AF_UNIX, $Cpanel::Socket::Constants::SOCK_STREAM | $Cpanel::Socket::Constants::SOCK_NONBLOCK, 0 ) or do {
        _send_errno_response( $courier, 'socketpair_failed' );
        return 0;
    };

    return 1;
}

sub _create_exec_subprocess ( $courier, $gave_stdin, $program, @args ) {

    return if !_socketpair_or_end( $courier, my $pio, my $cio );
    _DEBUG() && printf STDERR "socketpair stdin/stdout: %d<->%d\n", fileno $pio, fileno $cio;

    return if !_pipe_or_end( $courier, my $rerr, my $werr );
    _DEBUG() && printf STDERR "pipe stderr: %d<-%d\n", fileno $rerr, fileno $werr;

    return if !_pipe_or_end( $courier, my $rstatus, my $wstatus );

    return if !_pipe_or_end( $courier, my $r_end, my $w_end );
    Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($w_end);

    # Ideally we’d use Cpanel::Async::Exec here, but that uses
    # Proc::FastSpawn, which doesn’t indicate a reason when exec fails.
    # (See COBRA-9212 for what happened to an attempt to rectify that.)

    my $cpid;

    Cpanel::Try::try(
        sub {
            $cpid = Cpanel::Exec::forked(
                [ $program, @args ],
                sub {
                    if ($gave_stdin) {
                        open \*STDIN, '<&=', $cio or warn "redirect STDIN failed: $!";
                        Cpanel::FHUtils::Blocking::set_blocking( \*STDIN );
                    }
                    else {
                        close \*STDIN;
                    }

                    open \*STDOUT, '>&=', $cio  or warn "redirect STDOUT failed: $!";
                    open \*STDERR, '>&=', $werr or warn "redirect STDERR failed: $!";

                    Cpanel::FHUtils::Blocking::set_blocking($_) for ( \*STDOUT, \*STDERR );
                },
            );
        },
        'Cpanel::Exception::IO::ExecError' => sub {
            my $err = $@;
            local $! = 0 + $@->error();
            _send_errno_response( $courier, 'exec_failed' );
        },
        'Cpanel::Exception::IO::ForkError' => sub {
            my $err = $@;
            local $! = 0 + $@->error();
            _send_errno_response( $courier, 'fork_failed' );
        },
    );

    return ( $cpid, $pio, $rerr, $rstatus, $r_end );
}

1;
