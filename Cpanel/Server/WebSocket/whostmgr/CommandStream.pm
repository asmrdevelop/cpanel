package Cpanel::Server::WebSocket::whostmgr::CommandStream;

# cpanel - Cpanel/Server/WebSocket/whostmgr/CommandStream.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::whostmgr::CommandStream

=head1 DESCRIPTION

A WebSocket transport for L<Cpanel::CommandStream::Server>.

=head1 CALL SYNTAX

Specify a serialization via a C<serialization> in the URL query string.

The default serialization is C<JSON>; however, this is for simplicity’s
sake in interactive use. For production it is recommended to use a
binary serialization like L<Sereal> or
L<CBOR|https://tools.ietf.org/html/rfc7049> (unimplemented currently).

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Destruct::DestroyDetector
  Cpanel::Server::WebSocket::whostmgr
);

use AnyEvent    ();
use Promise::XS ();

use Net::WebSocket::Frame::binary ();

use Cpanel::CommandStream::Server ();
use Cpanel::Exception             ();
use Cpanel::Form                  ();
use Cpanel::LoadModule::Utils     ();

use constant {
    TIMEOUT => 86400,

    _VERSION => 1,

    _DEBUG => 0,
};

# overwritten in tests
our $_HEARTBEAT_TIMEOUT;

BEGIN {
    $_HEARTBEAT_TIMEOUT = 45;
}

#----------------------------------------------------------------------

sub _can_access ( $class, @args ) {
    return 0 if !$class->SUPER::_can_access(@args);

    _get_serializer();

    return 1;
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Constructor.

=cut

sub new ( $class, @ ) {
    my $serializer = _get_serializer();

    return bless { _serializer => $serializer }, $class;
}

=head2 $obj = I<CLASS>->run( $COURIER )

See L<Cpanel::Server::Handlers::WebSocket>.

=cut

sub run ( $self, $courier ) {
    my $write_watch_sr = \do { my $v = undef };

    my $cstream_obj = Cpanel::CommandStream::Server->new(
        $self->{'_serializer'},

        sub ($bytes) {

            # Prevent circular references: don’t refer to $self here.

            $courier->enqueue_send( 'binary', $bytes );

            return _flush_write_queue( $courier, $write_watch_sr );
        },
    );

    my $cv = AnyEvent->condvar();

    my $ws_r_watch;

    # For now, let’s just make this a simple client that always sends
    # a heartbeat every so often, regardless of the amount of traffic
    # that’s going across.
    my $heartbeat_timer;

    my $tidy_up_cr = sub {
        if ( my $frame = $courier->sent_close_frame() ) {
            $courier->flush_write_queue();

            my ( $code, $reason ) = $frame->get_code_and_reason();

            $code //= 'no code';

            $reason = "[$reason]" if defined $reason;
            $reason //= 'no reason';

            _DEBUG() && print STDERR "sent close: $code, $reason\n";
        }

        undef $heartbeat_timer;
        undef $ws_r_watch;

        $courier->close_socket();

        # We shouldn’t need this. If it fixes a DESTROY-at-global-destruction
        # warning, that means a circular reference has been introduced.
        # $cstream_obj->CLEAN_UP();

        $cv->();
    };

    $heartbeat_timer = AnyEvent->timer(
        after    => $_HEARTBEAT_TIMEOUT,
        interval => $_HEARTBEAT_TIMEOUT,
        cb       => sub {
            $courier->check_heartbeat();
            _flush_write_queue( $courier, $write_watch_sr );

            if ( $courier->sent_close_frame() ) {
                _DEBUG() && print STDERR "ws heartbeat timeout\n";

                $0 .= ' (ws heartbeat timeout)';

                $tidy_up_cr->();
            }
        },
    );

    $ws_r_watch = _create_read_watcher( $courier, $cstream_obj, $tidy_up_cr );

    $cv->recv();

    _DEBUG() && print STDERR "$$: event loop end\n";

    return;
}

sub _is_invalid_serialization ($serialization) {
    return $serialization !~ m<\A[A-Za-z]+\z>;
}

sub _get_serializer {
    my $form_hr = Cpanel::Form::parseform();

    my $serialization = $form_hr->{'serialization'} // 'JSON';

    my $ser_class = "Cpanel::CommandStream::Serializer::$serialization";

    my $is_bad_serialization = _is_invalid_serialization($serialization);

    $is_bad_serialization ||= do {
        my $ser_path = Cpanel::LoadModule::Utils::module_path($ser_class);

        local ( $@, $! );
        !eval { require $ser_path };
    };

    if ($is_bad_serialization) {
        my $msg = "Bad serialization: $serialization";

        die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', $msg );
    }

    _DEBUG() && warn "serialization: $serialization\n";

    return $ser_class->new();
}

sub _create_read_watcher ( $courier, $cstream_obj, $tidy_up_cr ) {    ## no critic qw(ManyArgs) - mis-parse
    my $fd = $courier->get_socket_fd();
    _DEBUG() && print STDERR "socket FD: $fd\n";

    my $read_err;

    return AnyEvent->io(
        fh   => $fd,
        poll => 'r',
        cb   => sub {
            _DEBUG() && print STDERR "socket input\n";

            my $buf_sr;

            if ( eval { $buf_sr = $courier->get_next_data_payload_sr(); 1 } ) {
                $read_err = undef;

                if ($buf_sr) {
                    _DEBUG() && warn "got ws message\n";

                    $cstream_obj->handle_message($buf_sr);

                    _DEBUG() && warn "post-handler\n";
                }
            }
            else {
                $read_err = $@;

                _DEBUG() && print STDERR "WS read failure\n";
            }

            if ($read_err) {
                if ( eval { $read_err->isa('IO::Framed::X::EmptyRead') } ) {
                    _DEBUG() && warn "tcp close\n";

                    $0 .= ' (TCP closed)';
                }
                else {
                    warn $read_err;
                }
            }
            elsif ( $courier->sent_close_frame() ) {
                _DEBUG() && warn "ws close\n";

                $0 .= ' (ws closed)';
            }
            else {
                return;
            }

            $tidy_up_cr->();
        },
    );
}

sub _flush_write_queue ( $courier, $write_watch_sr ) {
    if ( $courier->flush_write_queue() ) {
        _DEBUG() && printf STDERR "$$: flush complete\n";
        return undef;
    }

    _DEBUG() && printf STDERR "$$: flush incomplete\n";

    if ( !$$write_watch_sr ) {
        _DEBUG() && printf STDERR "$$: listening for socket writablity\n";

        my $deferred = Promise::XS::deferred();

        my $watch = AnyEvent->io(
            fh   => $courier->get_socket_fd(),
            poll => 'w',
            cb   => sub {
                if ( $courier->flush_write_queue() ) {
                    undef $$write_watch_sr;
                    $deferred->resolve();
                }
            },
        );

        $$write_watch_sr = [ $watch, $deferred->promise() ];
    }
    else {
        _DEBUG() && printf STDERR "$$: writability listener already active\n";
    }

    return ${$write_watch_sr}->[1];
}

1;
