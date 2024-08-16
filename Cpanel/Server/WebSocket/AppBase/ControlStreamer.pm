package Cpanel::Server::WebSocket::AppBase::ControlStreamer;

# cpanel - Cpanel/Server/WebSocket/AppBase/ControlStreamer.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::AppBase::ControlStreamer

=head1 SYNOPSIS

    package My::Streaming::Application;

    use parent qw(
        Cpanel::Server::WebSocket::AppBase::ControlStreamer
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

This is an intermediate class that wraps
L<Cpanel::Server::WebSocket::AppBase::Streamer> with logic to parse out
“control” frames. See below for details.

=head1 CONTROL MESSAGES

There is occasionally a need to communicate “out-of-band” from the
application itself. For example, a terminal application needs to send
resize information to the backend process so that the shell knows the
number of columns and rows to use.

Toward this end, WebSocket data messages that this module receives
are decoded as per the protocol described in
L<Cpanel::Server::WebSocket::AppStream>. Control message payloads are sent
to the end class’s C<_on_control_message()> method. Data message payloads
are stripped of their AppStream-protocol escaping so that the payload
that the backend application receives is the “true” payload.

=head1 SUBCLASS METHODS TO DEFINE

You need to define those methods described in
L<Cpanel::Server::WebSocket::AppBase::Streamer> B<EXCEPT>
C<_SHOULD_SEND_PAYLOAD_TO_APP()>, which this class defines.

You B<MUST> also define:

=head2 _on_control_message( $PAYLOAD )

Optional; receives the payload of any control message.

=cut

use parent qw(
  Cpanel::Server::WebSocket::AppBase::Streamer
);

use Cpanel::Server::WebSocket::AppStream ();

sub _SHOULD_SEND_PAYLOAD_TO_APP {
    my ( $self, $payload_sr ) = @_;

    # This will mutate $$payload_sr.
    return 1 if Cpanel::Server::WebSocket::AppStream::decode($payload_sr);

    $self->_on_control_message($$payload_sr);

    return 0;
}

1;
