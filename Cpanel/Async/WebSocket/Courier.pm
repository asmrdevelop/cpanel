package Cpanel::Async::WebSocket::Courier;

# cpanel - Cpanel/Async/WebSocket/Courier.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::WebSocket::Courier

=head1 SYNOPSIS

    $courier->send_text('¡Hola!');  # NB: UTF-8, not Unicode

    $courier->send_binary("\xff\xfe");

    $courier->on(
        text => sub ($bytes) { .. },
    );

    $courier->finish( 'SUCCESS', 'It was great, y’all!' )->then(
        sub ($resp_code_reason_ar) {
            # We got a response.
        },
    );

=head1 DESCRIPTION

This class encapsulates the necessary post-handshake logic for a WebSocket
session. It acts as a messenger (i.e., a “courier”) between the WebSocket
peer and the local application logic.

Normally this class is instantiated by the handshake logic rather than
directly.

This is a refinement of the interface presented in
L<Cpanel::Server::WebSocket::Courier>. Ideally this newer module should
eventually replace that one.

This module assumes use of L<AnyEvent>.

=head1 EVENTS

This object exposes the following events:

=head2 C<text>

Fired after a text message arrives. Receives the (UTF-8-encoded) payload.

=head2 C<binary>

Fired after a binary message arrives. Receives the payload.

=head2 C<message>

Fired when either a text or binary message is received. Note that this event
obscures whether the incoming message was text or binary.

=head2 C<close>

Fired after a close frame/message arrives B<if> that frame isn’t a response
to a frame we sent first. Receives the WebSocket close and
reason as arguments, parsed as per L<Net::WebSocket::Frame::close>’s
C<get_code_and_reason()> method.

Clarification: This will I<not> fire if the received message is a
response to a close frame that we sent ourselves. It also won’t fire
if the response is a different SUCCESS close than we sent.

=cut

#----------------------------------------------------------------------

use Scalar::Util ();

use Promise::ES6 ();

use Net::WebSocket::Endpoint::Client ();
use Net::WebSocket::Parser           ();
use Net::WebSocket::Frame::text      ();
use Net::WebSocket::Frame::binary    ();

use Cpanel::Async::WebSocket::Courier::Flusher ();

use Cpanel::Event::Emitter ();

use parent (
    'Cpanel::Destruct::DestroyDetector',
);

use constant EVENT_NAMES => (
    'message',
    'text',
    'binary',
    'close',
    'error',
);

# Altered in tests
our $_SUPPRESS_DESTROY_WARNING;

our $_PING_TIMEOUT;

BEGIN {
    $_PING_TIMEOUT = 30;
}

use constant {
    _TEXT_FRAME_CLASS   => 'Net::WebSocket::Frame::text',
    _BINARY_FRAME_CLASS => 'Net::WebSocket::Frame::binary',

    # It’s not worthwhile to compress very small messages.
    _MIN_DEFLATE_SIZE => 16,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class.

%OPTS are:

=over

=item * C<socket> - The socket to poll. Probably an L<IO::Socket::SSL>
instance but can also be a plain socket.

=item * C<framed> - The L<IO::Framed> instance that wraps C<socket>.

=item * C<subprotocol> - (optional) The WebSocket subprotocol that we
negotiated with the peer on handshake.

=item * C<on> - (optional) A hashref of listeners to create immediately.
See L</EVENTS>.

=item * C<compressor> - (optional) An instance of
L<Net::WebSocket::PMCE::Data>.

=back

=cut

sub new ( $class, %raw_opts ) {
    my %parts = %raw_opts{ 'socket', 'framed', 'subprotocol', 'compressor', 'on' };

    delete @raw_opts{ keys %parts };
    if ( my @extra = %raw_opts ) {
        die "$class: Unrecognized: @extra";
    }

    my $emitter = Cpanel::Event::Emitter->new();

    if ( my $on_hr = delete $parts{'on'} ) {
        validate_events($on_hr);

        for my $evttype ( EVENT_NAMES() ) {
            if ( my $cb = $on_hr->{$evttype} ) {
                $emitter->on( $evttype, $cb );
            }
        }
    }

    my $self = bless \%parts, $class;
    $self->{'emitter'} = $emitter;

    my $ept = Net::WebSocket::Endpoint::Client->new(
        parser => Net::WebSocket::Parser->new( $parts{'framed'} ),
        out    => $parts{'framed'},
    );
    $ept->do_not_die_on_close();

    $self->{'endpoint'} = $ept;

    my $compressor = $parts{'compressor'};
    my $socket     = $parts{'socket'};

    my $self_str = "$self";

    my @watchers;

    $self->{'last_peer_activity_time'} = AnyEvent->now();
    my $last_activity_sr = \$self->{'last_peer_activity_time'};

    my %state = (
        watchers => \@watchers,

        %parts{'framed'},

        flusher => Cpanel::Async::WebSocket::Courier::Flusher->new(
            %parts{ 'socket', 'framed' },

            on_writable_et => sub {
                $$last_activity_sr = AnyEvent->now();
            },
        ),
    );
    $self->{'state'} = \%state;

    my $on_readable_with_eval = sub {
        my $ok = eval {
            _on_readable( \%state, $emitter, $ept, $compressor );
            1;
        };

        if ( !$ok ) {
            $emitter->emit_or_warn( error => $@ );
            $$_ = undef for @watchers;
        }
    };

    my $read_w;
    $read_w = AnyEvent->io(
        fh   => $socket,
        poll => 'r',
        cb   => sub {

            # This callback needs to be valid even after $self is DESTROY()ed.
            # It also needs not to *prevent* $self from being destroyed.
            # Thus, we cannot store a reference to $self (or to anything that
            # contains it) in this closure.

            $$last_activity_sr = AnyEvent->now();

            $on_readable_with_eval->();
        },
    );

    push @watchers, \$read_w;

    my $weak_self = $self;
    Scalar::Util::weaken($weak_self);

    my $timer;
    $timer = AnyEvent->timer(
        after    => $_PING_TIMEOUT / 10,
        interval => $_PING_TIMEOUT / 10,
        cb       => sub {
            if ($weak_self) {

                # Don’t ping until it’s been at least $_PING_TIMEOUT
                # since the last peer activity or ping.
                return if AnyEvent->now() < $_PING_TIMEOUT + $$last_activity_sr;

                $ept->check_heartbeat();
                $$last_activity_sr = AnyEvent->now();

                $weak_self->_flush_write();

                if ( $ept->sent_close_frame() ) {
                    $$_ = undef for @watchers;
                }
            }
            else {
                $timer = undef;
            }
        },
    );

    push @watchers, \$timer;

    # In case the server sent messages along with the handshake response.
    # We delay so that the immediate consumer of this object has a
    # chance to register callbacks before we read.
    #
    # Prefer timer() rather than postpone() here because that way we get a
    # watcher object whose GC will cancel the callback if $self GCs before
    # another run through the event loop. (As of June 2020, postpone() is
    # just a wrapper around timer() anyway.)
    #
    $self->{'_init_on_reasonable_w'} = AnyEvent->timer(
        after => 0,
        cb    => sub {
            $on_readable_with_eval->();
        },
    );

    return $self;
}

=head2 promise() = I<OBJ>->send_text( $PAYLOAD )

Sends a B<UTF-8-encoded> (i.e., raw bytes) payload, marked as a text string.

The returned promise resolves when the message is fully given to the kernel.
In low traffic that’ll be right away, but if outgoing messages are backed up
then it may take a bit.

=cut

sub send_text ( $self, $payload ) {
    return $self->_send( _TEXT_FRAME_CLASS, $payload );
}

=head2 promise() = I<OBJ>->send_binary( $PAYLOAD )

Like C<send_text()> but marks the payload as binary instead.

=cut

sub send_binary ( $self, $payload ) {
    return $self->_send( _BINARY_FRAME_CLASS, $payload );
}

=head2 promise(\@code_reason) = I<OBJ>->finish( $CODE, [$REASON] )

Sends a close frame with the given $CODE and, optionally, $REASON.
$CODE is interpreted as described in L<Net::WebSocket::Frame::close>.
$REASON is, as with C<send_text()>, a UTF-8 encoded byte string.

Unlike with C<send_text()> and C<send_binary()>, this method’s returned
promise resolves not when the frame is sent, but when the peer’s response
is received. That promise resolves if (and only if) the response close frame
matches the one we sent.

=cut

sub finish ( $self, $code, $reason = undef ) {
    if ( $self->{'state'}{'_called_finish'} ) {
        die "Already finish()ed!";
    }

    $self->{'state'}{'_called_finish'} = [ $code, $reason ];

    return Promise::ES6->new(
        sub ( $y, $n ) {
            $self->{'state'}{'_finish_callbacks'} = [ $y, $n ];

            $self->{'endpoint'}->close( code => $code, reason => $reason );
            $self->_flush_write();
        }
    );
}

=head2 $protocol = I<OBJ>->get_subprotocol()

Returns the subprotocol given to the constructor.

=cut

sub get_subprotocol ($self) {
    return $self->{'subprotocol'};
}

=head2 $socket = I<OBJ>->get_socket()

Returns I<OBJ>’s underlying Perl socket.

=cut

sub get_socket ($self) {
    return $self->{'socket'};
}

=head2 $subscription = I<OBJ>->create_subscription( $EVENT_NAME, $CALLBACK )

A passthrough to an underlying L<Cpanel::Event::Emitter> instance’s
method of the same name.

=cut

sub create_subscription ( $self, $evtname, $cb ) {
    return $self->{'emitter'}->create_subscription( $evtname, $cb );
}

=head1 STATIC FUNCTIONS

=head2 validate_events( \%EVENTS )

Validates a hash reference of event listeners. If anything in %EVENTS
is truthy but invalid, an exception that reports the problem will
be thrown.

=cut

sub validate_events ($events_hr) {
    my %copy = %$events_hr;
    delete @copy{ EVENT_NAMES() };

    if ( my @extra = keys %copy ) {
        die "Unrecognized event(s): @extra";
    }

    if ( my @invalid = grep { $_ && ( 'CODE' ne ref ) } values %$events_hr ) {
        die "Invalid event listener: @invalid";
    }

    return;
}

#----------------------------------------------------------------------

sub _send ( $self, $frame_class, $payload ) {
    return Promise::ES6->new(
        sub ( $y, $n ) {

            # NB: We’ve withheld an implementation of fragmentation here
            # to mitigate the complexity of branching in this function.
            # Talk to Cobra if that logic is needed.

            my $msg;

            if ( $self->{'compressor'} && length $payload > _MIN_DEFLATE_SIZE ) {
                $msg = $self->{'compressor'}->create_message(
                    $frame_class,
                    $payload,
                );
            }
            else {
                $msg = $frame_class->new( payload => $payload );
            }

            $self->{'framed'}->write(
                $msg->to_bytes(),
                sub {
                    $y->();
                }
            );

            $self->_flush_write();
        }
    );
}

sub _flush_write ($self) {
    return $self->{'state'}{'flusher'}->flush();
}

# Called from tests. We wouldn’t ordinarily call this in production
# because every WebSocket session should end with close frames, which
# cause the watchers to be cleared. Tests, though, sometimes do partial
# WebSocket sessions, which requires manual clearing of the watchers.
#
sub _clear_watchers ($self) {
    $$_ = undef for @{ $self->{'state'}{'watchers'} };

    $self->{'state'}{'flusher'}->stop();

    return;
}

#----------------------------------------------------------------------

sub _on_readable ( $state_hr, $emitter, $endpoint, $compressor ) {

    while ( my $msg = $endpoint->get_next_message() ) {
        my $payload;

        $payload = $msg->get_payload();

        if ( $compressor && $compressor->message_is_compressed($msg) ) {
            $payload = $compressor->decompress($payload);
        }

        $emitter->emit( $msg->get_type() => $payload );

        $emitter->emit( message => $payload );
    }

    # Net::WebSocket will auto-send responses for close or ping frames,
    # but because we use a write queue it doesn’t actually *send* those
    # responses; it just enqueues them. So we have to flush if there’s
    # anything in the queue.
    $state_hr->{'flusher'}->flush() if $state_hr->{'framed'}->get_write_queue_count();

    if ( my $got = $endpoint->received_close_frame() ) {
        _handle_received_close( $state_hr, $emitter, $got );
    }

    return;
}

sub _handle_received_close ( $state_hr, $emitter, $got ) {
    _clear_watchers_in_state($state_hr);

    if ( my $sent_ar = $state_hr->{'_called_finish'} ) {
        my $success_code = _WS_SUCCESS_CODE();

        my $sent_close_code = _close_code_to_number( $sent_ar->[0] );

        my ( $res, $rej ) = @{ delete $state_hr->{'_finish_callbacks'} };

        my @got_parts = $got->get_code_and_reason();

        my $sent_str = _stringify_close_code_and_reason( $sent_close_code, $sent_ar->[1] );
        my $got_str  = _stringify_close_code_and_reason( $got->get_code_and_reason() );

        # If both endpoints reported success then don’t fail on that,
        # even if they reported different reasons.
        my $success = $sent_close_code == $success_code;
        $success &&= $got_parts[0] == $success_code;

        # If both endpoints didn’t succeed and the other close doesn’t
        # match us, that’s a failure, even if the peer reported success.
        $success ||= ( $sent_str eq $got_str );

        if ($success) {
            $res->( \@got_parts );
        }
        else {
            $emitter->emit_or_warn( close => $got->get_code_and_reason() );
            $rej->("Close response mismatch: sent [$sent_str] got [$got_str]");
        }
    }
    else {
        $emitter->emit_or_warn( close => $got->get_code_and_reason() );
    }

    return;
}

sub _WS_SUCCESS_CODE {
    my $frame = Net::WebSocket::Frame::close->new( code => 'SUCCESS' );

    return ( $frame->get_code_and_reason() )[0];
}

sub _close_code_to_number ($code) {
    return $code if !length $code;

    my $frame = Net::WebSocket::Frame::close->new( code => $code );

    return ( $frame->get_code_and_reason() )[0];
}

sub _stringify_close_code_and_reason ( $code, $reason ) {
    return join( q< >, grep { length } $code, $reason );
}

sub _clear_watchers_in_state ($state_hr) {
    $$_ = undef for @{ $state_hr->{'watchers'} };

    return;
}

sub DESTROY ($self) {

    # If we finish()ed this object, then we need to stick around to
    # resolve finish()’s returned promise. Otherwise let’s clear out
    # the watchers.
    my $ept = $self->{'endpoint'};

    my $did_not_close    = !$ept->sent_close_frame();
    my $clobber_watchers = $did_not_close || $ept->received_close_frame();

    if ($clobber_watchers) {
        warn "$self: DESTROY()ed without closing!\n" if $did_not_close && !$_SUPPRESS_DESTROY_WARNING;
        _clear_watchers_in_state( $self->{'state'} );
    }

    $self->SUPER::DESTROY();

    return;
}

1;
