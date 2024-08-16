package Cpanel::CommandStream::Client;

# cpanel - Cpanel/CommandStream/Client.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client

=head1 SYNOPSIS

    my $client = Cpanel::CommandStream::Client->new();

    my $tracker_obj = Cpanel::Async::PromiseTracker->new();

    # Give this to a caller.
    my $requestor = $client->create_requestor(
        $to_send_cr,
        $tracker_obj,
    );

    $client->handle_message( \%message )

=head1 DESCRIPTION

This module implements I<basic> client logic for CommandStream. It lacks
any transport-layer logic and thus is mostly for code internal to
CommandStream.

As of this writing the only CommandStream transport is WebSocket;
for logic to make such a connection see
L<Cpanel::CommandStream::Client::WebSocket::Base>.

=head1 RELATIONSHIP WITH L<Cpanel::CommandStream::Client::Requestor>

Promise implementations that derive from the Promise/A+ specification
implement “deferred” and “promise” objects. These two objects implement
the “push” and “pull” parts, respectively, of the workflow; neither
object is useful without the other. (cf. L<Promise::XS> et al.)

This class and L<Cpanel::CommandStream::Client::Requestor> share a
similar relationship: the “requestor” is what sends a query to the
server, while the “client” is what handles responses to those queries.

We could, of course, implement both sets of functionality in a single
class; however, that would be less-optimal separation of concerns.
On a practical level, that would also make it harder to avoid circular
references (and the resulting memory leaks).

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Cpanel::CommandStream::Client::Requestor ();
use Cpanel::CommandStream::Client::Control   ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return bless {
        id_callback => {},
    }, $class;
}

=head2 $req = I<OBJ>->create_requestor( $SENDER_CR, $PROMISE_TRACKER )

Creates a L<Cpanel::CommandStream::Client::Requestor> instance
from I<OBJ>.

$SENDER_CR receives a list of key-value pairs that constitute a
CommandStream message.

$PROMISE_TRACKER is the WebSocket connection’s
L<Cpanel::Async::PromiseTracker> instance. It will be given to each
created request object.

$req is what you give to code that needs to make requests.

=cut

sub create_requestor ( $self, $to_send_cr, $promise_tracker ) {    ## no critic qw(ManyArgs) - mis-parse
    return Cpanel::CommandStream::Client::Requestor->new(
        $self, $to_send_cr, $promise_tracker,
    );
}

=head2 $req = I<OBJ>->handle_message( \%MESSAGE )

Handles %MESSAGE, dispatching the relevant callbacks as needed.

You’ll probably give a closure around this method to your
transport layer’s “on-message” mechanism.

=cut

sub handle_message ( $self, $msg_hr ) {
    my $id = $msg_hr->{'id'} // do {
        my @kv = %$msg_hr;
        warn "No id?? (@kv)";
        return;
    };

    my $cb = $self->{'id_callback'}{$id} or do {
        my @kv = %$msg_hr;
        warn "No callback for ID $id (@kv)";
        return;
    };

    my $ctrl = $self->{'id_callback_ctrl'}{$id} ||= do {
        Cpanel::CommandStream::Client::Control->new( \$self->{'id_forgotten'}{$id} );
    };

    local $@;
    warn if !eval {
        $cb->( $self->{'id_callback_ctrl'}{$id}, $msg_hr );
        1;
    };

    if ( $self->{'id_forgotten'}{$id} ) {
        delete $self->{$_}{$id}
          for (
            'id_callback',
            'id_callback_ctrl',
            'id_forgotten',
          );
    }

    return;
}

# for testing:
sub _id_is_known ( $self, $id ) {
    return !!$self->{'id_callback'}{$id};
}

1;
