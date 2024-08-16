package Cpanel::Async::LocalPush;

# cpanel - Cpanel/Async/LocalPush.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::LocalPush

=head1 SYNOPSIS

    my $pusher = Cpanel::Async::LocalPush->new();

    $pusher->send( 'MessageType', $payload );

One-liner:

    perl -MAnyEvent -MCpanel::Async::LocalPush -e'my $cv = AnyEvent->condvar(); my $push = Cpanel::Async::LocalPush->new(); $push->send( MyNotes => "¡Hola!" )->finally($cv); $cv->recv()'

=head1 DESCRIPTION

This module facilitates sending notifications to “listener” cPanel & WHM
processes. See L<Cpanel::Async::LocalPush::Pull> for that “listener” logic.

The underlying transport is abstracted by design.

This module assumes use of L<AnyEvent>.

=head1 PROBLEMS & SOLUTIONS

=over

=item * This module cannot currently provide robust delivery guarantees;
thus, the “puller” process must account for the possibility of a dropped
message. For example, poll every 5 seconds or so in tandem with your
listener.

=item * If you send strings that might contain non-UTF-8,
apply a secondary encoding (e.g., base64, URI) before sending.

=back

=cut

#----------------------------------------------------------------------
# INTERNAL IMPLEMENTATION NOTES:
#
# D-Bus is used here because its ubiquity makes it something of an obvious
# choice for this application; however, owing to reliability issues that
# have surfaced with the service historically, it’s not a transport
# mechanism we can consider “reliable”.
#
# Other candidates were/are:
#
#   - ZeroMQ: Can’t handle multiple concurrent publishers to the same
#       channel.
#
#   - Netlink user sockets: Unreliable, channels are numeric.
#
#   - Netlink generic sockets: Unreliable, requires a custom kernel module.
#
#   - NSQ/Gearman/etc.: Requires management of a separate service.
#       There are other uses for such a message queue service, however.
#
# In theory, this module should be able to migrate to a different
# transport if we were to consider such an improvement.
#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Promise::ES6                     ();
use Protocol::DBus::Client::AnyEvent ();

use Cpanel::Async::LocalPush::Constants ();
use Cpanel::JSON                        ();
use Cpanel::UTF8::Strict                ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return bless {
        _dbus => Protocol::DBus::Client::AnyEvent::system(),
    }, $class;
}

=head2 promise() = I<OBJ>->send( $CHANNEL, $BODY )

Sends a message. $CHANNEL may consist only of A-Z, a-z, and _.

$BODY may be any JSON-compatible scalar or data structure.

=cut

sub send ( $self, $channel, $body ) {
    my $json;

    local $@;
    eval {
        _validate_channel($channel);

        $json = Cpanel::JSON::Dump($body);

        # Protocol::DBus expects decoded strings.
        Cpanel::UTF8::Strict::decode($json);

        1;
    } or do {
        return Promise::ES6->reject($@);
    };

    return $self->_initialize_p()->then(
        sub ($msgr) {
            return $msgr->send_signal(
                path      => $Cpanel::Async::LocalPush::Constants::DBUS_PUSH_PATH,
                interface => 'com.cpanel.Push',
                member    => $channel,
                signature => 's',
                body      => [$json],
            );
        }
    );
}

#----------------------------------------------------------------------

sub _validate_channel ($channel) {
    if ( !length $channel || $channel =~ tr<A-Za-z_><>c ) {
        die "Invalid channel: “$channel”";
    }

    return;
}

sub _initialize_p ($self) {
    return $self->{'_init_p'} ||= $self->{'_dbus'}->initialize();
}

1;
