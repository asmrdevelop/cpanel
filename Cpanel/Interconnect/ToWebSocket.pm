package Cpanel::Interconnect::ToWebSocket;

# cpanel - Cpanel/Interconnect/ToWebSocket.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Interconnect::ToWebSocket

=head1 SYNOPSIS

    my $ic = Cpanel::Interconnect::ToWebSocket->new( $fh, $websocket );

    $ic->on( progress => sub ($bytes) { .. } );

    $ic->run()->then( sub { .. } );

=head1 DESCRIPTION

This class contains logic to send all data from a filehandle to a
WebSocket peer.

=head1 EVENTS

The following events exist:

=over

=item * C<progress> - Fired every time a chunk is sent to WebSocket.
Its payload is the number of (payload) bytes that were sent just prior.

=item * C<message> - Fired every time a message is received. Its payload
is the message text, as an octet string.

=back

See below for controls to create listeners for these.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::Destruct::DestroyDetector',
);

use AnyEvent     ();
use Promise::ES6 ();

use Cpanel::Autodie        ();
use Cpanel::Event::Emitter ();
use Cpanel::Exception      ();
use Cpanel::Time::Split    ();

use constant {
    _DEBUG     => 0,
    _READ_SIZE => 2**17,
};

our ( $_TIMER_INTERVAL, $_GENERAL_TIMEOUT, $_INACTIVITY_TIMEOUT );

BEGIN {

    # Overridden in tests:
    $_TIMER_INTERVAL     = 5;
    $_INACTIVITY_TIMEOUT = 30 * 60;
    $_GENERAL_TIMEOUT    = 2 * 86400;
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $FILEHANDLE, $WEBSOCKET )

Instantiates this class. $FILEHANDLE is a Perl filehandle, and $WEBSOCKET
is a L<Cpanel::Async::WebSocket::Courier>.

=cut

sub new ( $class, $fh, $ws ) {
    my $emitter = Cpanel::Event::Emitter->new();
    return bless { _fh => $fh, _ws => $ws, _emit => $emitter }, $class;
}

#----------------------------------------------------------------------

=head2 $subscription = I<OBJ>->create_subscription( $TYPE => $HANDLER_CR )

Passthrough to an underlying L<Cpanel::Event::Emitter> object’s method
of the same name. This is how to create listeners for I<OBJ>’s events.

=cut

sub create_subscription ( $self, $type, $handler_cr ) {
    return $self->{'_emit'}->create_subscription( $type, $handler_cr );
}

=head2 promise() = I<OBJ>->run()

Reads from the object’s Perl filehandle until it’s done, sending each
chunk to the WebSocket along the way. The returned promise resolves
when the last chunk is sent out.

This does I<NOT> C<finish()> the WebSocket object; you need to do that
yourself.

=head3 Timeouts

This times out:

=over

=item * … if 30 minutes pass without reading anything from the local
filehandle

=item * … after 2 days, regardless of anything else.

=back

Timeout is indicated via a L<Cpanel::Exception::Timeout> rejection.

=cut

sub run ($self) {
    die 'Already ran!' if exists $self->{'ran'};

    $self->{'ran'} = undef;

    $self->{'stream_r'} = undef;
    my $stream_r_ref = \$self->{'stream_r'};

    my $timer;

    return Promise::ES6->new(
        sub ( $y, $n ) {
            @{$self}{ 'res', 'rej' } = ( $y, $n );

            # The below duplicates _fail() in order to avoid
            # a memory leak.
            my $fail_cr = sub ($why) {
                undef $$stream_r_ref;
                $n->($why);
            };

            $timer = $self->_create_timer($fail_cr);

            my $emitter = $self->{'_emit'};

            $self->{'_on_message'} = $self->{'_ws'}->create_subscription(
                message => sub ($payload) {
                    $emitter->emit( message => $payload );
                },
            );

            $self->{'_close_sub'} = $self->{'_ws'}->create_subscription(
                close => sub ( $code, $reason ) {
                    _debug('received close frame');

                    $fail_cr->("Got premature close ($code $reason) from remote!");
                }
            );

            $self->{'_error_sub'} = $self->{'_ws'}->create_subscription(
                error => sub ($what) {
                    _debug( "received WebSocket error - " . __PACKAGE__ );

                    $fail_cr->($what);
                }
            );

            $self->_start_reading_fh();
        }
    )->finally( sub { $timer = undef; } );
}

sub _create_timer ( $self, $fail_cr ) {
    my $start = AnyEvent->now();

    my $inactivity_count = 0;
    $self->{'inactivity_count_r'} = \$inactivity_count;

    my $inactivity_count_max = $_INACTIVITY_TIMEOUT / $_TIMER_INTERVAL;

    return AnyEvent->timer(
        after    => $_TIMER_INTERVAL,
        interval => $_TIMER_INTERVAL,
        cb       => sub {
            if ( ( AnyEvent->now() - $start ) > $_GENERAL_TIMEOUT ) {
                $fail_cr->( Cpanel::Exception::create_raw( 'Timeout', "Timeout: " . Cpanel::Time::Split::seconds_to_locale($_GENERAL_TIMEOUT) ) );
            }
            else {
                $inactivity_count++;

                if ( $inactivity_count > $inactivity_count_max ) {
                    $fail_cr->( Cpanel::Exception::create_raw( 'Timeout', "Inactivity timeout: " . Cpanel::Time::Split::seconds_to_locale($_INACTIVITY_TIMEOUT) ) );
                }
            }
        },
    );
}

sub _fail ( $self, $why ) {
    $self->_stop_reading_fh();
    $self->{'rej'}->($why);

    return;
}

sub _resolve ($self) {
    $self->_stop_reading_fh();
    $self->{'res'}->();

    return;
}

sub _stop_reading_fh ($self) {
    undef $self->{'stream_r'};

    return;
}

sub _is_reading_fh ($self) {
    return !!$self->{'stream_r'};
}

sub _start_reading_fh ($self) {
    my ( $stream_fh, $ws ) = @{$self}{ '_fh', '_ws' };

    my $emitter = $self->{'_emit'};

    my $inactivity_count_r = $self->{'inactivity_count_r'};

    $self->{'stream_r'} = AnyEvent->io(
        fh   => $stream_fh,
        poll => 'r',
        cb   => sub {
            $$inactivity_count_r = 0;

            local $@;

            $self->_fail($@) if !eval {
                if ( Cpanel::Autodie::sysread_sigguard( $stream_fh, my $buf, _READ_SIZE ) ) {
                    _debug( sprintf 'sending %d bytes', length $buf );

                    my $sent;
                    my $p = $ws->send_binary($buf)->then(
                        sub {
                            $emitter->emit( progress => length $buf );
                            $sent = 1;
                        },

                        sub ($why) {
                            $self->_fail($why);
                        },
                    );

                    # This assumes that our promises don’t do the end-of-loop
                    # deferral that the Promises/A+ specification requires.
                    # See Promise::ES6’s documentation for more details.
                    if ( !$sent && $self->_is_reading_fh() ) {
                        _debug('pausing stream to give peer time to catch up');

                        $self->_stop_reading_fh();

                        $p->then(
                            sub {
                                _debug('resuming stream');
                                $self->_start_reading_fh();
                            }
                        );
                    }
                }
                else {
                    _debug('finished');

                    $self->_resolve();
                }

                1;
            };
        },
    );

    return;
}

sub _debug ($str) {
    print STDERR "$str\n" if _DEBUG;
    return;
}

1;
