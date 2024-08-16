package Cpanel::Server::WebSocket::Courier;

# cpanel - Cpanel/Server/WebSocket/Courier.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::Courier - WebSocket messaging provider

=head1 SYNOPSIS

    my $courier = Cpanel::Server::WebSocket::Courier->new(
        socket => $client_socket,
        compressor => $pmce_data_object,
    );

=head1 DESCRIPTION

This module exposes methods that a WebSocket application needs to
communicate with its client.

=cut

use Socket ();

use IO::Framed                       ();
use Net::WebSocket::Parser           ();
use Net::WebSocket::Endpoint::Server ();
use Net::WebSocket::Message          ();

use Cpanel::IO::FramedFlush ();
use Cpanel::TCP::Close      ();

use constant {
    _MIN_COMPRESS_PAYLOAD => 3,
};

# Exposed for testing:
our $_CLOSE_RESPONSE_MAX_WAIT_TIME = 60 * 60;    # 1 hour

=head1 PUBLIC METHODS

=head2 I<CLASS>->new( %OPTS )

Instantiates this class. %OPTS are:

=over

=item * C<socket> Required. The socket to the WebSocket client.

=item * C<compressor> Optional. An instance of L<Net::WebSocket::PMCE::Data>.

=item * C<max_pings> Optional. Given to L<Net::WebSocket::Endpoint::Server>’s
constructor.

=back

=cut

sub new {
    my ( $class, %opts ) = @_;

    die 'need “socket”' if !$opts{'socket'};

    $opts{"_$_"} = delete $opts{$_} for keys %opts;

    my $io_framed = IO::Framed->new( $opts{'_socket'} )->enable_write_queue();
    $opts{'_io_framed'} = $io_framed;

    $opts{'_ept'} = Net::WebSocket::Endpoint::Server->new(
        parser    => Net::WebSocket::Parser->new($io_framed),
        out       => $io_framed,
        max_pings => $opts{'_max_pings'},
    );

    $opts{'_ept'}->do_not_die_on_close();

    return bless \%opts, $class;
}

=head2 I<OBJ>->get_socket_bitmask()

Returns the client socket’s bitmask. This is useful for integrating
into C<select()> loops and the like.

=cut

sub get_socket_bitmask {
    vec( my $mask, fileno( $_[0]{'_socket'} ), 1 ) = 1;
    return $mask;
}

=head2 I<OBJ>->get_socket_fd()

Returns the client socket’s file descriptor. This is useful for integrating
into event loops.

=cut

sub get_socket_fd ($self) {
    return fileno( $self->{'_socket'} );
}

=head2 I<OBJ>->enqueue_send( FRAME_CLASS, PAYLOAD )

Enqueues an unfragmented message with the given C<PAYLOAD> to be sent.
(C<flush_write_queue()> will then actually send the message.)

The message will be compressed if
(and only if) there is compression support and if the referred payload
is long enough to justify it. (There is currently no way to forcibly
disable compression for a given payload, but it would be trivial to add.)

C<FRAME_CLASS> is either a full class name or just C<text> and C<binary>,
which will map to the appropriate L<Net::WebSocket::Frame> subclass. (We
assume that that class is loaded.)

=cut

sub enqueue_send {
    my ( $self, $frame_class ) = @_;

    return $self->{'_io_framed'}->write( $self->_create_ws_message( $frame_class, $_[2] )->to_bytes() );
}

=head2 I<OBJ>->get_write_queue_count()

Passthrough to L<IO::Framed::Write>’s method.

=cut

sub get_write_queue_count {
    my ($self) = @_;

    return $self->{'_io_framed'}->get_write_queue_count();
}

=head2 I<OBJ>->flush_write_queue()

Passthrough to L<IO::Framed::Write>’s method.

=cut

sub flush_write_queue {
    my ($self) = @_;

    return $self->{'_io_framed'}->flush_write_queue();
}

=head2 I<OBJ>->finish([ CODE [, REASON ] ])

Sends a close frame with the given CODE and REASON, then flushes the write
queue and closes the socket.

CODE may be a numeric WebSocket exit code or a string that matches one of
L<Net::WebSocket::Frame::close>’s named constants (e.g., C<SUCCESS>,
C<POLICY_VIOLATION>).

REASON, if given, is a string
that describes the reason for session termination. This string B<MUST>
conform to WebSocket’s length and formatting requirements for a close frame.

This waits “a while” for the peer to close the TCP connection.
If that doesn’t happen then we give up and close it ourselves.

Both parameters are optional, but REASON requires that CODE be given. You
should probably always at least give a CODE.

Example:

    $courier->finish( 'SUCCESS' );

See also L<Net::Async::WebSocket::Courier>’s implementation of
similar logic, which adds a verification of the peer’s response close
frame.

=cut

sub finish {
    my ( $self, $code, $reason ) = @_;

    $self->{'_ept'}->close( code => $code, reason => $reason );

    #We don’t care about failures here since we’re closing the
    #connection anyway.
    local $@;
    eval { Cpanel::IO::FramedFlush::flush_with_determination( $self->{'_io_framed'} ); };

    my $endpoint = $self->{'_ept'};

    _await_close_response( $endpoint, $self->{'_socket'} );

    $self->close_socket();

    if ( my $close_resp = $self->{'_ept'}->received_close_frame() ) {
        ( $code, $reason ) = $endpoint->sent_close_frame()->get_code_and_reason();

        my ( $code2, $reason2 ) = $close_resp->get_code_and_reason();

        $_ //= 0 for ( $code, $code2, $reason2 );

        if ( $code != $code2 ) {
            warn "$0: Sent WebSocket close $code; received $code2 (reason=$reason2)\n";
        }
    }

    return;
}

sub _await_close_response ( $ept, $socket ) {

    # We don’t really care if this fails:
    shutdown $socket, Socket::SHUT_WR;

    my $rin = q<>;
    vec( $rin, fileno($socket), 1 ) = 1;

    my $end_of_close_wait = time + $_CLOSE_RESPONSE_MAX_WAIT_TIME;

    while (1) {
        my $remaining = $end_of_close_wait - time;

        # We could warn on timeouts, but it would probably
        # just be noise in the log.
        last if $remaining < 0;

        my $rout = $rin;

        my $out = select( $rout, undef, undef, $remaining );

        if ( $out > 0 ) {

            # Discard data messages:
            local $@;
            eval { $ept->get_next_message() };

            my $err = $@;

            if ($err) {
                last if eval { $err->isa('IO::Framed::X::EmptyRead') };

                warn $err;
            }
        }
        elsif ( $out < 0 ) {

            # Tolerate SIGCHLD et al.:
            next if $!{'EINTR'};

            warn "Failure ($!) while awaiting WebSocket peer closure; closing …\n";
            last;
        }
    }

    return;
}

=head2 I<OBJ>->close_socket()

Closes the socket without sending a WebSocket close.

=cut

sub close_socket {

    # no need to warn as the socket is getting closed
    Cpanel::TCP::Close::close_avoid_rst( $_[0]{'_socket'} );

    return;
}

=head2 I<OBJ>->get_next_data_payload_sr()

Similar to L<Net::WebSocket::Endpoint::Server>’s C<get_next_message()>
method, but whereas C<get_next_message()> returns a L<Net::WebSocket::Message>
instance, this method returns a reference to an octet string that contains
the message’s payload.

If there isn’t a message ready, undef is returned.

Because there should always be a WebSocket close prior to the end of
the connection, an empty read will prompt a thrown
L<IO::Framed::X::EmptyRead> exception.

=cut

sub get_next_data_payload_sr {
    my ($self) = @_;

    my $msg = $self->{'_ept'}->get_next_message();
    return $msg && $self->_get_message_payload_sr($msg);
}

=head2 I<OBJ>->check_heartbeat()

Passthrough to L<Net::WebSocket::Endpoint::Server>’s method.

=cut

sub check_heartbeat {
    my ($self) = @_;

    return $self->{'_ept'}->check_heartbeat();
}

=head2 I<OBJ>->sent_close_frame()

Passthrough to L<Net::WebSocket::Endpoint::Server>’s method.

=cut

sub sent_close_frame {
    my ($self) = @_;

    return $self->{'_ept'}->sent_close_frame();
}

=head2 I<OBJ>->is_closed()

Passthrough to L<Net::WebSocket::Endpoint::Server>’s method.

=cut

sub is_closed {
    my ($self) = @_;

    return $self->{'_ept'}->is_closed();
}

#----------------------------------------------------------------------

sub _get_message_payload_sr {
    my ( $self, $msg ) = @_;

    #Just because we *can* compress messages doesn’t mean
    #that every message is (or should be) compressed.
    if ( $self->{'_compressor'} && $self->{'_compressor'}->message_is_compressed($msg) ) {
        return \$self->{'_compressor'}->decompress( $msg->get_payload() );
    }

    return \$msg->get_payload();
}

sub _create_ws_message {
    my ( $self, $class ) = @_;    #$_[2] == message payload

    if ( index( $class, ':' ) == -1 ) {
        substr( $class, 0, 0, 'Net::WebSocket::Frame::' );
    }

    if ( $self->{'_compressor'} && length( $_[2] ) >= $self->_MIN_COMPRESS_PAYLOAD() ) {
        return $self->{'_compressor'}->create_message(
            $class,
            $_[2],
        );
    }

    return $class->new( payload => $_[2] );
}

1;
