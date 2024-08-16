package Cpanel::Server::WebSocket::AppBase::Streamer;

# cpanel - Cpanel/Server/WebSocket/AppBase/Streamer.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::AppBase::Streamer

=head1 SYNOPSIS

    package My::Streaming::Application;

    use parent qw(
        Cpanel::Server::WebSocket::AppBase::Streamer
    );

    use Net::WebSocket::Frame::text ();

    use constant {
        _FRAME_CLASS => 'Net::WebSocket::Frame::text',
        _STREAMER    => 'My::Streamer::Module',     #lazy-loaded
    };

    #NOTE: See Cpanel::Server::Handlers::WebSocket for other methods
    #that a WebSocket module needs to define.

    #----------------------------------------------------------------------

    package main;

    my $stream_app = My::Streaming::Application->new();

    $stream_app->run( $courier_obj, @streamer_args );

=head1 DESCRIPTION

This base class interconnects a WebSocket client (via a socket)
and a L<Cpanel::Streamer> object (the “application”). This module
itself, then, functions as a router between the client and the
application.

Operation is pretty straightforward: Any input from the application is sent
to the client in one or more data frames, and the payload of any data
message that we get from the client is by default sent to the application.
A subclass can implement a custom C<_SHOULD_SEND_PAYLOAD_TO_APP()> method if it’s
desired to process some messages otherwise; for example, a shell application
must transmit window size changes out of band from the stream that carries
the shell’s actual data.

Despite that seeming simplicity, the internals here are rather complex
because of the number of things that can go awry in a setup like this.

There’s some duplication here with L<Cpanel::Interconnect>. The WebSocket
mechanics make it awkward to try to deduplicate code with that module,
unfortunately.

=head1 SUBCLASS METHODS TO DEFINE

=head2 _STREAMER()

Required; should return the name of the L<Cpanel::Streamer> subclass that
will power this application.

=head2 _FRAME_CLASS()

Optional; defaults to L<Net::WebSocket::Frame::binary>.

=head2 _SHOULD_SEND_PAYLOAD_TO_APP( \$PAYLOAD )

Optional; receives a reference to the payload of all messages.
If this returns falsy, the payload is discarded; otherwise, it’s sent
to the app. Note that this method may alter the payload or handle it
other than by sending to the app. (See subclasses for example uses of this.)

=head2 _CHILD_ERROR_TO_WEBSOCKET_CLOSE( $CHILD_ERROR )

By default, if a process exits in failure the server sends WebSocket
INTERNAL_ERROR (1011) as the close code, with an empty reason. If you
want a different behavior, define this optional method, which receives
the $CHILD_ERROR (C<$?>) and should return a code and, optionally,
a reason to send to the client. The code given may be anything that
L<Net::WebSocket::Frame::close>’s constructor understands.

If no code is returned then this falls back to the default behavior
(code 1011 with no reason).

=head1 PROTECTED METHODS

=head2 _HEARTBEAT_TIMEOUT()

The number of seconds we wait between pings.

=cut

use Try::Tiny;

use parent qw(
  Cpanel::AttributeProvider
  Cpanel::Server::WebSocket::AppBase
);

use IO::Framed                       ();
use IO::SigGuard                     ();
use Net::WebSocket::Endpoint::Server ();
use Net::WebSocket::Parser           ();

use Cpanel::Autodie          qw(sysread_sigguard);
use Cpanel::Debug            ();
use Cpanel::Exception        ();
use Cpanel::IO::FramedFlush  ();
use Cpanel::IO::SelectHelper ();
use Cpanel::LoadModule       ();

BEGIN {
    *_sysread = *Cpanel::Autodie::sysread_sigguard;
}

# Used in testing to check a race condition.
our $_AFTER_FORK_CR;

use constant {
    DEBUG => 0,

    _EINTR  => 4,
    _EIO    => 5,
    _EAGAIN => 11,

    _READ_CHUNK        => 65536,
    _HEARTBEAT_TIMEOUT => 30,

    _TTL_SOURCE_FLUSH_AFTER_CLOSE => 60,
};

use constant _CHILD_ERROR_TO_WEBSOCKET_CLOSE => ();

# IO::Framed::Write doesn’t expose a buffer size, but it does
# expose the number of pending messages. It’s a bit “roundabout”
# of a way to implement a buffer size limit, but since we’ll never
# generate a message that exceeds the pipe/socket buffer size,
# this achieves a reliable--if inexact--buffer size limit for the
# client.
#
# It *doesn’t*, though, achieve a reliable buffer size limit for the app.
# The unreliability is because we don’t have as reliable of control over
# the incoming WebSocket message size. However, that’s not as pressing of
# a concern because, if there’s going to be an ongoing speed disparity
# between the client and the backend app, the client is more likely to be
# the slower one. That may change if we stream to an app that itself has
# to apply backpressure to this process, but that’s not a concern for now.
#
# Linux’s default pipe buffer is 64 KiB, so this limits the app-to-WebSocket
# buffer to about 64 MiB.
our $_MAX_WRITE_QUEUE_COUNT = 1_000;

# For testing only.
our $ON_BACKPRESSURE;

sub _STREAMER { die 'ABSTRACT' }

=head1 METHODS

=head2 I<CLASS>->new()

Returns an instance of the end class.

=cut

sub new {
    my ($class) = @_;

    Cpanel::LoadModule::load_perl_module( $class->_STREAMER() );
    Cpanel::LoadModule::load_perl_module( $class->_FRAME_CLASS() );

    return $class->SUPER::new();
}

=head2 * C<OBJ>->run( COURIER, @STREAMER_ARGS )

Runs the application. COURIER is an instance of
L<Cpanel::Server::WebSocket::Courier>; further arguments are passed
to the C<_STREAMER()> instance.

=cut

sub run {
    my ( $self, $courier, @streamer_args ) = @_;

    #sanity
    die Cpanel::Exception->create_raw('need courier!') if !$courier;

    local ( $!, $@ );

    my $child_pid;

    # By default Perl restarts select() automatically if SIGCHLD arrives while
    # select() waits for input. This would be bad for us because we’d wait
    # for the select() timeout before we reap the child process.
    # Rather than do that, let’s track SIGCHLD ourselves.
    # This prevents Perl from restarting the select()
    # and allows us to decide how to proceed.
    #
    # NB: This also alleviates the need for a self-pipe or any other
    # trick to interrupt a select/poll/epoll because that action will
    # end with EINTR, which we manage.

    my $reap_cr = sub {
        local $?;

        # A sanity-check:
        die '$child_pid isn’t set?!??!' if !$child_pid;

        while (1) {
            my $reaped_pid = waitpid( -1, 1 );

            last if $reaped_pid == -1;

            if ( $reaped_pid != $child_pid ) {

                # This will only happen if there’s another child process,
                # which really shouldn’t happen, but just in case, let’s
                # look for this condition and report it.
                warn "Got SIGCHLD, but reaped PID ($reaped_pid) doesn’t match expected child PID ($child_pid)!";
            }
            else {
                $self->{'_child_err'} = $?;

                _debug("$$ got SIGCHLD (CHILD_ERROR=$self->{'_child_err'})");

                $SIG{'CHLD'} = 'DEFAULT';    ##no critic qw(RequireLocalizedPunctuationVars);
            }
        }
    };

    my $reap_after_set_child_pid;

    local $SIG{'CHLD'} = sub {
        $self->{'_got_sigchld'} = 1;

        # We need to tolerate the case where the child process exits
        # immediately, before the parent process can manipulate its
        # memory to track the PID, etc. When that happens, we set
        # $need_pre_reap so that, once we’ve set $child_pid, we know
        # to do a reap
        #
        if ($child_pid) {
            $reap_cr->();
        }
        else {
            $reap_after_set_child_pid = 1;
        }
    };

    my $streamer = $self->_STREAMER()->new(@streamer_args);

    $_AFTER_FORK_CR->() if $_AFTER_FORK_CR;

    $child_pid = $streamer->get_attr('pid');

    $reap_cr->() if $reap_after_set_child_pid;

    $self->set_attr( 'streamer', $streamer );

    my $select_helper = Cpanel::IO::SelectHelper->new(
        client   => $courier->get_socket_bitmask(),
        from_app => $streamer->get_attr('from'),
        to_app   => $streamer->get_attr('to'),
    );

    @{$self}{'_select_helper'} = ($select_helper);

    #If the application disappears, we need to send the client
    #a WebSocket close. That can’t happen if SIGPIPE murders
    #us before we can send the close frame.
    local $SIG{'PIPE'} = 'IGNORE';

    my ( $client_is_gone, $interconnect_error );

    try {
        $self->_interconnect( $courier, $streamer );
    }
    catch {
        _debug("interconnect error: $_");
        $interconnect_error = $_;
    };

    _debug( "last fh: " . ( $self->{'_last_fh'} // '' ) );

    if ( !$self->{'_got_sigchld'} && ( 'client' eq $self->{'_last_fh'} ) ) {
        $client_is_gone = 1;
    }

    if ($client_is_gone) {
        $self->_respond_to_client_going_away( $courier, $streamer );
    }
    else {
        $self->_respond_to_source_going_away( $courier, $interconnect_error );
    }

    return;
}

=head2 I<CLASS>->authorize( HANDLER_OBJ )

Either return if the client is authorized to run this module,
or C<die()> with an appropriate exception if not. HANDLER_OBJ
is an instance of L<Cpanel::Server::Handlers::WebSocket>.

=cut

use constant authorize => ();

#----------------------------------------------------------------------
# Notes on the logic below:
#
#EPIPE here will propagate as an exception and end the session.
#This is by design so that we can respond appropriately
#whether EPIPE is from the client or the application.
#
#DEBUG && _debug(...) - This avoids no-op function calls in a tight loop.
#----------------------------------------------------------------------

sub _interconnect {
    my ( $self, $courier, $streamer ) = @_;

    my $select_helper = $self->{'_select_helper'};

    my %flusher = (
        client => $courier,
        to_app => IO::Framed->new( $streamer->get_attr('to') )->enable_write_queue(),
    );
    $self->{'_flusher'} = \%flusher;

    my $from_app_fh = $streamer->get_attr('from');

    my $app_wtr = $flusher{'to_app'};

    my $rin = $select_helper->get_bitmask( 'client', 'from_app' );

    my ( $rout, $wout );

  IO:
    while (1) {
        my $win = $select_helper->get_bitmask( $self->_get_pending_flusher_writers() );

        if ( !grep { tr<\0><>c } ( $rin, $win ) ) {
            _debug("done reading and writing (client closed in error)");
            last IO;
        }

        if ( $self->_app_is_finished() && !$courier->get_write_queue_count() ) {
            _debug('app is gone, and its last output is flushed');
            last IO;
        }

        #This appears only to be necessary if the child leaves
        #something open that should be closed; e.g., $pty->close_slave().
        #last IO if $self->_app_is_finished() && !$win;

        $rout = $rin;

        # Backpressure to the app, in case the socket peer reads slowly.
        # See above discussion re $_MAX_WRITE_QUEUE_COUNT.
        if ( $courier->get_write_queue_count() > $_MAX_WRITE_QUEUE_COUNT ) {
            DEBUG && _debug("Backpressure to app! (client is slow)");
            $ON_BACKPRESSURE->('app')                                 if $ON_BACKPRESSURE;
            $select_helper->remove_from_bitmask( \$rout, 'from_app' ) if $select_helper->matches_bitmask( 'from_app', $rout );
        }

        # Backpressure to the socket, in case the app reads slowly.
        # See above discussion re $_MAX_WRITE_QUEUE_COUNT.
        if ( $app_wtr->get_write_queue_count() > $_MAX_WRITE_QUEUE_COUNT ) {
            DEBUG && _debug("Backpressure to client! (app is slow)");
            $ON_BACKPRESSURE->('client')                            if $ON_BACKPRESSURE;
            $select_helper->remove_from_bitmask( \$rout, 'client' ) if $select_helper->matches_bitmask( 'client', $rout );
        }

        DEBUG && _debug( sprintf "select() read-in: %v.08b",  $rout );
        DEBUG && _debug( sprintf "select() write-in: %v.08b", $win );

        my $result = select( $rout, $wout = $win, undef, $self->_HEARTBEAT_TIMEOUT() );

        if ( $result == 0 ) {
            if ( $courier->is_closed() ) {
                warn "Timed out while waiting to flush final write queue contents!";
                last IO;
            }
            else {
                $courier->check_heartbeat();
                next IO;
            }
        }
        elsif ( $result == -1 ) {

            #Don’t report the error if it’s EINTR since it could have been
            #SIGCHLD, which we need to listen for.
            if ( $! == _EINTR() ) {
                _debug("select() got EINTR");
                next;
            }

            die Cpanel::Exception->create_raw("select(): $!");
        }

        DEBUG && _debug( sprintf "select() read-out: %v.08b",  $rout );
        DEBUG && _debug( sprintf "select() write-out: %v.08b", $wout );

        $self->{'_last_op'} = 'write';

        if ($wout) {
            for my $wtr_name ( 'client', 'to_app' ) {
                if ( $select_helper->matches_bitmask( $wtr_name => $wout ) ) {
                    DEBUG && _debug("flushing to $wtr_name");
                    $self->{'_last_fh'} = $wtr_name;
                    $flusher{$wtr_name}->flush_write_queue();
                }
            }
        }

        $self->{'_last_op'} = 'read';

        #Read from client
        if ( $select_helper->matches_bitmask( client => $rout ) ) {
            $self->_read_from_client( \$rin, $courier, $app_wtr );
        }

        #Read from the upstream source, but only if the client
        #didn’t go away already.
        if ( length($rin) && $select_helper->matches_bitmask( from_app => $rout ) ) {
            $self->_read_from_application( \$rin, $from_app_fh, $courier );
        }
    }

    if ( $self->_app_is_finished() ) {
        $self->_read_and_send_app_last_output($courier);
    }

    _debug("done interacting");

    return;
}

use constant _SHOULD_SEND_PAYLOAD_TO_APP => 1;

sub _read_from_client {
    my ( $self, $rin_sr, $courier, $app_wtr ) = @_;

    DEBUG && _debug('reading from client');

    $self->{'_last_fh'} = 'client';

    #We don’t always get a $msg; the message might be fragmented,
    #for example, or only part of a frame might have arrived.
    #Or, what came in was just a ping or a pong, which the
    #Endpoint object handles automatically.
    try {
        if ( my $payload_sr = $courier->get_next_data_payload_sr() ) {
            if ( $self->_SHOULD_SEND_PAYLOAD_TO_APP($payload_sr) ) {

                # There’s no point in sending to the app
                # if we already know it’s gone. We also need not to send
                # an empty input to $app_wtr because of:
                #
                #   https://github.com/FGasper/p5-IO-Framed/issues/4
                #
                if ( length($$payload_sr) && !$self->_app_is_finished() ) {
                    $app_wtr->write($$payload_sr);

                    #We probably don’t need to select() before flushing;
                    #even if we do, flush_write_queue() will just no-op.
                    $self->{'_last_fh'} = 'to_app';
                    DEBUG && _debug("quick-flushing to app");
                    $app_wtr->flush_write_queue();
                }
            }
        }
        elsif ( $courier->sent_close_frame() ) {
            _debug("sent close");

            #A WebSocket close is more like a close() than a TCP
            #shutdown(SHUT_WR): if the client has sent a close frame,
            #then that client is finished, and all that’s left is to
            #flush to_app and shut things down.

            #There’s nothing more to read from the client,
            #and there’s no point to reading from the source,
            #either, since we’re just going to throw it away.
            #
            $$rin_sr = q<>;
        }
    }
    catch {
        _debug( "client read error: " . ( ref($_) || $_ ) );

        #If we get nothing from the client, then it’s game-over
        #for the entire session, so no more reading from anything.
        $$rin_sr = q<>;

        #An empty read means our client closed down the TCP link
        #without shutting down WebSocket.
        #That’s not something we want to warn on. There might be
        #other failures that we want to ignore, but for now let’s
        #treat any other failure as something we should report.
        if ( !try { $_->isa('IO::Framed::X::EmptyRead') } ) {
            local $@ = $_;
            warn;
        }
    };

    return;
}

#https://stackoverflow.com/questions/43108221/reading-from-forkpty-child-process-ls-output-yields-eio
#Sometimes a pty will fail with EIO instead of the normal
#EOF behavior. This can happen if SIGCHLD is received after
#select() but before read(). (And possibly in other cases?)
#The following accounts for that.
sub _failure_is_weird_tty_EIO_case {
    my ( $errno, $fh ) = @_;

    my $is_weird_tty_EIO_case = -t $fh;
    $is_weird_tty_EIO_case &&= $errno == _EIO;

    return $is_weird_tty_EIO_case;
}

sub _read_from_application {
    my ( $self, $rin_sr, $from_app_fh, $courier ) = @_;

    DEBUG && _debug('reading from from_app');

    $self->{'_last_fh'} = 'from_app';

    my ( $buf, $did_read );
    my $ok = eval {
        $did_read = _sysread( $from_app_fh, $buf, $self->_READ_CHUNK() );
        1;
    };

    if ( !$ok ) {
        my $err = $@;

        my $is_weird_tty_EIO_case = _failure_is_weird_tty_EIO_case(
            $err->get('error'),
            $from_app_fh,
        );

        if ( !$is_weird_tty_EIO_case ) {
            local $@ = $err;
            die;
        }
    }

    if ($did_read) {
        $courier->enqueue_send( $self->_FRAME_CLASS(), $buf );

        #We probably don’t need to select() before flushing;
        #even if we do, flush_write_queue() will just no-op.
        $self->{'_last_fh'} = 'client';
        DEBUG && _debug("quick-flushing to client");
        $courier->flush_write_queue();
    }
    else {
        _debug("source stopped writing");

        #All we know at this point is that the app
        #has stopped talking. It still might be listening,
        #in which case the client can still gainfully send
        #messages to it.

        $self->{'_select_helper'}->remove_from_bitmask( $rin_sr, 'from_app' );

        #Don’t close(from_app) here in case from_app is
        #the same OS file descriptor as to_app (e.g., a pty)
    }

    return;
}

sub _get_pending_flusher_writers {
    my ($self) = @_;

    my @names;

    for my $name ( keys %{ $self->{'_flusher'} } ) {
        push @names, $name if $self->{'_flusher'}{$name}->get_write_queue_count();
    }

    return @names;
}

sub _read_and_send_app_last_output {
    my ( $self, $courier ) = @_;

    _debug('checking for final output from app');

    my $from_app_fh = $self->get_attr('streamer')->get_attr('from');

    # 1) Finish reading from the app.
    # We record the chunks individually so that we don’t
    # send an over-large message.
    my @output;
    while ( sysread $from_app_fh, my $buf, $self->_READ_CHUNK() ) {
        push @output, $buf;
    }

    if ($!) {
        my $err        = $!;
        my $report_err = ( $err != _EAGAIN() );
        $report_err &&= !_failure_is_weird_tty_EIO_case( $err, $from_app_fh );

        if ($report_err) {
            warn "Failed to clear out application filehandle: $err";
        }
    }

    #2) If we got anything, send it to the client.
    if (@output) {
        _debug( sprintf 'sending final output from app (%d chunks)', 0 + @output );
        $courier->enqueue_send( $self->_FRAME_CLASS(), $_ ) for @output;
    }

    return;
}

#NORMAL END TO TRANSACTION: client sends a close frame
#(NB: We’ve already sent a response close frame.)
#
#   close client socket
#   flush app writer
#   close app writer & app reader
#   wait for graceful finish, then terminate() source
#
#We also call this when the client goes away. This isn’t a normal end
#to the session, but we respond in the same way.
#
sub _respond_to_client_going_away {
    my ( $self, $courier, $streamer ) = @_;

    _debug("closing client socket");
    $courier->close_socket();

    _debug("flushing to_app");
    $self->_flush_app_with_determination();

    _debug("closing app filehandles");
    $self->_close_app_filehandles($streamer);

    _debug("finishing app process");
    $self->_finish_app__trap_die();

    return;
}

sub _close_app_filehandles {
    my ( $self, $streamer ) = @_;

    my $to_fh   = $streamer->get_attr('to');
    my $from_fh = $streamer->get_attr('from');

    my @to_close = ( 'to_app' => $to_fh );
    if ( fileno($to_fh) != fileno($from_fh) ) {
        push @to_close, ( from_app => $from_fh );
    }

    while ( my ( $name, $fh ) = splice @to_close, 0, 2 ) {
        close($fh) or warn "close($name): $!";
    }

    return;
}

sub _finish_app__trap_die {
    my ($self) = @_;

    #This could fail, if the subclass makes it so.
    try {
        $self->_finish_app();
    }
    catch {
        warn "failed to finish source: $_";
    };

    return;
}

sub _flush_app_with_determination {
    my ( $self, $name ) = @_;

    my $framed_obj = $self->{'_flusher'}{'to_app'};

    try {
        require Cpanel::IO::FramedFlush;
        Cpanel::IO::FramedFlush::flush_with_determination($framed_obj);
    }
    catch {
        warn "failed to flush “$name”: $!";
    };

    return 1;
}

sub _respond_to_source_going_away {
    my ( $self, $courier, $interconnect_error ) = @_;

    Cpanel::Debug::log_warn($interconnect_error) if $interconnect_error;

    #e.g., SIGCHLD
    if ( $self->_app_is_finished() ) {
        _debug("source finished ($self->{'_child_err'}), now to close");

        $courier->finish( $self->_app_ws_code_and_reason( $self->{'_child_err'} ) );

        _debug("did finish()");
    }
    else {
        _debug("source NOT finished … ?");

        #We got here because the source wasn’t done but an I/O operation
        #with it still failed. In this case, we treat that I/O error as
        #the error to report to the client. This state is thus always a
        #failure.

        $courier->finish('INTERNAL_ERROR');

        $self->_finish_app__trap_die();
    }

    return;
}

# If the app finished up, then we assume that the failure from
# interacting with the source came about because we tried to
# interact with a process that already had ended.
#
# Thus, the success/failure that we indicate to the client depends
# on the source’s reported success/failure, not the I/O error that
# got us here in the first place.
sub _app_ws_code_and_reason {
    my ( $self, $child_error ) = @_;

    if ($child_error) {
        my ( $code, $reason );

        try {
            ( $code, $reason ) = $self->_CHILD_ERROR_TO_WEBSOCKET_CLOSE($child_error);
        }
        catch {
            local $@ = $_;
            warn;
        };

        if ( !$code ) {
            my $ref = ref $self;
            warn "$ref $$: Unreported CHILD_ERROR: $child_error\n";

            $code = 'INTERNAL_ERROR';
        }

        return ( $code, $reason // () );
    }

    return 'SUCCESS';
}

sub _app_is_finished {
    my ($self) = @_;

    return !!$self->{'_got_sigchld'};
}

sub _finish_app {
    my ($self) = @_;

    #We can’t just kill the application right away because it might
    #still be finishing up its affairs. So give it a bit of time
    #to finish up before we forcibly kill it.
    my $stop_at = time + _TTL_SOURCE_FLUSH_AFTER_CLOSE;

    #Wait for our SIGCHLD handler to set _child_err.
    #(As a bonus, SIGCHLD will interrupt sleep()!)
    while ( time < $stop_at ) {
        last if defined $self->{'_child_err'};
        sleep 1;
    }

    $self->{'_child_err'} //= $self->get_attr('streamer')->terminate();

    return;
}

sub _debug {
    DEBUG && printf STDERR "DEBUG:%s:%s\n", scalar(localtime), shift;
    return;
}

1;
