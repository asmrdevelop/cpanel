package Cpanel::Async::LocalPush::Pull;

# cpanel - Cpanel/Async/LocalPush/Pull.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::LocalPush::Pull

=head1 SYNOPSIS

    my $puller = Cpanel::Async::LocalPush::Pull->new();

    my $subscr = $puller->create_subscription( MessageType => sub ($msg) {
        ...
    } );

One-liner to listen for C<MyNotes> messages:

    perl -MAnyEvent -MCpanel::Async::LocalPush::Pull -e'my $pull = Cpanel::Async::LocalPush::Pull->new(); my $subscr = $pull->create_subscription( MyNotes => sub { print "msg: [$_[0]]\n" } ); AnyEvent->condvar()->recv()'

=head1 DESCRIPTION

This module is the listener counterpart to L<Cpanel::Async::LocalPush>.
See that module for more information about this IPC mechanism.

This module assumes use of L<AnyEvent>.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Protocol::DBus::Client::AnyEvent ();

use Cpanel::Async::LocalPush::Constants ();
use Cpanel::Context                     ();
use Cpanel::JSON                        ();
use Cpanel::Event::Emitter              ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    my $dbus = Protocol::DBus::Client::AnyEvent::system();

    my $emitter = Cpanel::Event::Emitter->new();

    my $self = bless { dbus => $dbus, emitter => $emitter }, $class;

    # NB: If this callback references $self, then
    # we’ll have a reference cycle and leak memory.
    $dbus->on_signal( sub { _on_signal( $emitter, @_ ) } );

    return $self;
}

=head2 $subscription = I<OBJ>->create_subscription( $CHANNEL, $CALLBACK )

Creates a subscription to $CHANNEL. While the returned object lives,
$CALLBACK will receive every message from $CHANNEL that I<OBJ> receives.

=cut

sub create_subscription ( $self, $channel, $cb ) {
    Cpanel::Context::must_not_be_void();

    my $emitter_subscr = $self->{'emitter'}->create_subscription( $channel, $cb );

    $self->_add_match($channel);

    return Cpanel::Async::LocalPush::Pull::Subscription->new(
        $self,
        $channel,
        $emitter_subscr,
    );
}

#----------------------------------------------------------------------

sub _match_op ( $self, $fn, $member ) {
    return $self->{'dbus'}->initialize()->then(
        sub ($msgr) {
            $msgr->send_call(
                member      => $fn,
                destination => 'org.freedesktop.DBus',
                interface   => 'org.freedesktop.DBus',
                path        => '/org/freedesktop/DBus',
                signature   => 's',
                body        => ["path='$Cpanel::Async::LocalPush::Constants::DBUS_PUSH_PATH',member='$member'"],
            );
        }
    );
}

sub _add_match ( $self, $member ) {
    return $self->_match_op( 'AddMatch', $member );
}

sub _remove_match ( $self, $member ) {
    return $self->_match_op( 'RemoveMatch', $member );
}

sub _on_signal ( $emitter, $msg ) {

    # We check PATH in order to reject, e.g., NameAcquired &c.
    if ( $msg->get_header('PATH') eq $Cpanel::Async::LocalPush::Constants::DBUS_PUSH_PATH ) {
        $emitter->emit(
            $msg->get_header('MEMBER'),
            $msg->get_body() && do {
                my $json = $msg->get_body()->[0];

                # Protocol::DBus’s returned strings are decoded.
                utf8::encode($json);

                Cpanel::JSON::Load($json);
            },
        );
    }

    return;
}

#----------------------------------------------------------------------

package Cpanel::Async::LocalPush::Pull::Subscription;

use cPstrict;

use parent 'Cpanel::Destruct::DestroyDetector';

sub new ( $class, $puller, $name, $emitter_subscr ) {
    return bless {
        puller       => $puller,
        name         => $name,
        subscription => $emitter_subscr,
    }, $class;
}

sub DESTROY ($self) {
    $self->{'puller'}->_remove_match( $self->{'name'} );

    return;
}

1;
