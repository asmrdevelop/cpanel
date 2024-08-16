package Net::WebSocket::Frame::ping;

=encoding utf-8

=head1 NAME

Net::WebSocket::Frame:ping:

=head1 SYNOPSIS

    my $frm = Net::WebSocket::Frame::ping->new(

        #Optional, can be either empty (default) or four random bytes
        mask => q<>,

        payload => $payload,
    );

    $frm->get_type();           #"ping"

    $frm->is_control();   #1

    my $mask = $frm->get_mask_bytes();

    my $payload = $frm->get_payload();

    my $serialized = $frm->to_bytes();

Note that, L<as per RFC 6455|https://tools.ietf.org/html/rfc6455#section-5.5>,
ping messages can have only up to 125 bytes in their payload.

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Base::ControlFrame
);

use constant get_opcode => 9;

1;
