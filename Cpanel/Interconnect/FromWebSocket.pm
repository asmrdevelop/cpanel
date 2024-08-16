# cpanel - Cpanel/Interconnect/FromWebSocket.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::Interconnect::FromWebSocket;

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Interconnect::FromWebSocket

=head1 SYNOPSIS

    my $ic = Cpanel::Interconnect::FromWebSocket->new( $fh, $websocket );

    $ic->on( progress => sub ($bytes) { .. } );

    $ic->run()->then( sub { .. } );

=head1 DESCRIPTION

This class contains logic to write all data from a WebSocket peer to
a filehandle.

=head1 EVENTS

This class subclasses L<Cpanel::Event::Emitter>. The following events
exist:

=over

=item * C<progress> - Fired every time a chunk is received from WebSocket.
Its payload is the number of (payload) bytes that were received just prior.

=back

=head1 SEE ALSO

This module has a counterpart for pushing data from a filehandle to a
WebSocket peer: C<Cpanel::Interconnect::ToWebSocket>.

=cut

use parent qw(
  Cpanel::Destruct::DestroyDetector
  Cpanel::Event::Emitter
);

use AnyEvent::Handle ();
use Promise::ES6     ();

use constant {
    _DEBUG => 0,
};

=head1 METHODS

=head2 $obj = I<CLASS>->new( $FILEHANDLE, $WEBSOCKET )

Instantiates this class. $FILEHANDLE is a Perl filehandle, and $WEBSOCKET
is a L<Cpanel::Async::WebSocket::Courier>.

=cut

sub new ( $class, $fh, $ws ) {
    return bless { _fh => $fh, _ws => $ws }, $class;
}

=head2 promise() = I<OBJ>->run()

Read from the WebSocket until it’s done, sending each chunk to the object’s
Perl filehandle along the way. The returned promise resolves when the
WebSocket receives a close from the remote.

=cut

sub run ($self) {

    die 'Already ran!' if exists $self->{'ran'};

    $self->{'ran'} = undef;

    my $ws_sr = \$self->{'_ws'};

    my $write_queue;
    my @subscriptions;

    my $cleanup_cr = sub {
        undef $$ws_sr;
        undef $write_queue;

        @subscriptions = ();
    };

    return Promise::ES6->new(
        sub ( $y, $n ) {

            $write_queue = AnyEvent::Handle->new(
                fh       => $self->{'_fh'},
                on_error => sub ( $hdl, $fatal, $msg ) {
                    $n->($msg);
                    $hdl->destroy();
                }
            );

            push @subscriptions, $$ws_sr->create_subscription(
                error => sub ($why) {
                    _debug("WebSocket error: $why");
                    $n->("WebSocket error: $why");
                }
            );

            push @subscriptions, $$ws_sr->create_subscription(
                binary => sub ($bytes) {
                    _debug( sprintf 'received binary frame of %d bytes', length $bytes );
                    $self->emit( progress => length $bytes );
                    $write_queue->push_write($bytes);
                }
            );

            push @subscriptions, $$ws_sr->create_subscription(
                close => sub {
                    _debug('received close frame');

                    $write_queue->on_drain(
                        sub {
                            _debug('all data written to file handle');
                            $y->();
                        }
                    );

                }
            );

        }
    )->finally($cleanup_cr);
}

sub _debug ($str) {
    print STDERR "$str\n" if _DEBUG;
    return;
}

1;
