package Cpanel::CommandStream::Courier;

# cpanel - Cpanel/CommandStream/Courier.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Courier

=head1 SYNOPSIS

    my $courier = Cpanel::CommandStream::Courier->new( $id, $send_cr );

=head1 DESCRIPTION

This “messenger” class abstracts a CommandStream transport mechanism.
This allows handler modules to send messages without worrying about the
transport implementation.

Each instance of this class represents a single (multiplexed) CommandStream
request and its response.

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->( $REQUEST_ID, $SEND_CR )

Instantiates this class. $REQUEST_ID is the ID to attach to each
outgoing message.

$SEND_CR is a callback that sends the message (as a hash reference).
Its return B<MUST> be one of:

=over

=item * undef, which indicates that more data may be sent. (The message
itself may or may not have been sent.)

=item * a promise, which indicates that more data may NOT currently
be sent. The promise B<MUST> resolve only when the transport layer can
accept more messages.

=back

=cut

sub new ( $class, $req_id, $send_msg_cr ) {    ## no critic qw(ManyArgs) - mis-parse
    my %self = (
        _req_id          => $req_id,
        _send_message_cr => $send_msg_cr,
    );

    return bless \%self, $class;
}

=head2 $undef_or_promise = I<OBJ>->send_response( $MSG_CLASS [, \%PAYLOAD ] )

Sends a response to the client’s CommandStream request. $MSG_CLASS is the
message’s C<class>. %PAYLOAD, if given, is the message’s content.

Examples:

    $courier->send_response('start_ok');

This sends a message whose C<class> is C<start_ok>. Other than C<id>,
the message will have no other content.

    $courier->send_response('failed', { why => 'just because' });

This sends a message whose C<class> is C<failed>. It will contain an
C<id> as well as C<why>.

This returns the result of C<new()>’s $SEND_CR parameter.

=cut

sub send_response ( $self, $msg_class, $payload_hr = undef ) {
    $payload_hr //= {};

    local $payload_hr->{'class'} = $msg_class;
    local $payload_hr->{'id'}    = $self->{'_req_id'};

    return $self->{'_send_message_cr'}->($payload_hr);
}

1;
