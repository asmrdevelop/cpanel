package Cpanel::Server::WebSocket::AppStream;

# cpanel - Cpanel/Server/WebSocket/AppStream.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::AppStream - The AppStream protocol

=head1 SYNOPSIS

    if (Cpanel::Server::WebSocket::AppStream::decode( \$ws_payload)) {
        _parse_as_data($ws_payload);
    }
    else {
        _parse_as_control($ws_payload);
    }

=head1 DESCRIPTION

The “AppStream” protocol facilitates the transmission of messages not
intended for the actual streamed application. This is useful, e.g., to give
cpsrvd an instruction while it interconnects a client with a streamed
application.  AppStream uses an encoding that mimics SMTP’s “dot-stuffing”
encoding:

=over

=item * Prefix each control payload with a single C<.> to indicate that
this is a control message.

=item * If a data payload already begins with C<.>, then prefix an
additional C<.>.

=back

Note that no control payload can begin with C<.> (prior to encoding, that is).
Encoder logic should FAIL any attempts to encode such a payload.

=head1 FUNCTIONS

=head2 decode( PAYLOAD_SR )

Mutates PAYLOAD_SR (a reference to an octet string) so that it contains
the (decoded) AppStream payload.

Returns one of the following:

=over

=item * 1 - for a data payload

=item * 0 - for a control payload

=back

=cut

sub decode {
    if ( index( ${ $_[0] }, '.' ) == 0 ) {
        substr( ${ $_[0] }, 0, 1, q<> );

        #If there was only a single “.” at the beginning,
        #then this is a control payload.
        if ( index( ${ $_[0] }, '.' ) != 0 ) {
            return 0;
        }
    }

    return 1;
}

1;
