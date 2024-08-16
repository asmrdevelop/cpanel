package Net::WebSocket::Frame;

=encoding utf-8

=head1 NAME

Net::WebSocket::Frame

=head1 SYNOPSIS

    #Never instantiate Net::WebSocket::Frame directly;
    #always call new() on a subclass:
    my $frame = Net::WebSocket::Frame::text->new(
        fin => 0,                   #to start a fragmented message
        rsv => 0b11,                #RSV2 and RSV3 are on
        mask => "\x01\x02\x03\x04   #clients MUST include; servers MUST NOT
        payload => \'Woot!',
    );

    $frame->get_fin();
    $frame->get_mask_bytes();
    $frame->get_payload();

    $frame->set_rsv();
    $frame->get_rsv();

    $frame->to_bytes();     #for sending over the wire

=head1 DESCRIPTION

This is the base class for all frame objects. The interface as described
above should be fairly straightforward.

=head1 EXPERIMENTAL: CUSTOM FRAME CLASSES

You can have custom frame classes, e.g., to support WebSocket extensions that
use custom frame opcodes. RFC 6455 allocates opcodes 3-7 for data frames and
11-15 (0xb - 0xf) for control frames.

The best way to do this is to subclass either
L<Net::WebSocket::Base::DataFrame> or L<Net::WebSocket::Base::ControlFrame>,
depending on what kind of frame you’re dealing with.

An example of such a class is below:

    package My::Custom::Frame::booya;

    use strict;
    use warnings;

    use parent qw( Net::WebSocket::Base::DataFrame );

    use constant get_opcode => 3;

    use constant get_type => 'booya';

Note that L<Net::WebSocket::Parser> still won’t know how to handle such a
custom frame, so if you intend to receive custom frames as part of messages,
you’ll also need to create a custom base class of this class, then also
subclass L<Net::WebSocket::Parser>. You may additionally want to subclass
L<Net::WebSocket::Streamer::Server> (or -C<::Client>) if you do streaming.

B<NOTE: THIS IS LARGELY UNTESTED.> I’m not familiar with any application that
actually requires this feature. The C<permessage-deflate> extension seems to
be the only one that has much widespread web browser support.

=cut

use strict;
use warnings;

use parent qw(
    Net::WebSocket::Base::Typed
);

use Net::WebSocket::Constants ();
use Net::WebSocket::Mask ();
use Net::WebSocket::X ();

use constant {
    FIRST2 => 0,
    LEN_LEN => 1,
    MASK => 2,
    PAYLOAD => 3,

    _RSV1 => chr(4 << 4),
    _RSV2 => chr(2 << 4),
    _RSV3 => chr(1 << 4),
};

#fin, rsv, mask, payload
#rsv is a bitmask of the three values, with RSV1 as MOST significant bit.
#So, represent RSV1 and RSV2 being on via 0b110 (= 4 + 2 = 6)
sub new {
    my $class = shift;

    my ( $fin, $rsv, $mask, $payload_sr );

    #We loop through like this so that we can get a nice
    #syntax for “payload” without copying the string.
    #This logic should be equivalent to a hash.
    while (@_) {
        my $key = shift;

        #“payload_sr” (as a named argument) is legacy
        if ($key eq 'payload' || $key eq 'payload_sr') {
            if (!ref $_[0]) {
                if (defined $_[0]) {
                    $payload_sr = \shift;
                }
                else {
                    shift;
                    next;
                }
            }
            elsif ('SCALAR' eq ref $_[0]) {
                $payload_sr = shift;
            }
            else {
                die Net::WebSocket::X->create('BadArg', $key => shift, 'Must be a scalar or SCALAR reference.');
            }
        }
        elsif ($key eq 'fin') {
            $fin = shift;
        }
        elsif ($key eq 'rsv') {
            $rsv = shift;
        }
        elsif ($key eq 'mask') {
            $mask = shift;
        }
        else {
            warn sprintf("Unrecognized argument “%s” (%s)", $key, shift);
        }
    }

    my $type = $class->get_type();

    my $opcode = $class->get_opcode($type);

    if (!defined $fin) {
        $fin = 1;
    }

    $payload_sr ||= \do { my $v = q<> };

    my ($byte2, $len_len) = $class->_assemble_length($payload_sr);

    if (defined $mask) {
        _validate_mask($mask);

        if (length $mask) {
            $byte2 |= "\x80";
            Net::WebSocket::Mask::apply($payload_sr, $mask);
        }
    }
    else {
        $mask = q<>;
    }

    my $first2 = chr $opcode;
    $first2 |= "\x80" if $fin;

    if ($rsv) {
        die "“rsv” must be < 0-7!" if $rsv > 7;
        $first2 |= chr( $rsv << 4 );
    }

    substr( $first2, 1, 0, $byte2 );

    return bless [ \$first2, \$len_len, \$mask, $payload_sr ], $class;
}

# All string refs: first2, length octets, mask octets, payload
sub create_from_parse {
    return bless \@_, shift;
}

sub get_mask_bytes {
    my ($self) = @_;

    return ${ $self->[MASK] };
}

#To collect the goods
sub get_payload {
    my ($self) = @_;

    my $pl = "" . ${ $self->[PAYLOAD] };

    if (my $mask = $self->get_mask_bytes()) {
        Net::WebSocket::Mask::apply( \$pl, $mask );
    }

    return $pl;
}

#For sending over the wire
sub to_bytes {
    my ($self) = @_;

    return join( q<>, map { $$_ } @$self );
}

sub get_rsv {
    my ($self) = @_;

    #0b01110000 = 0x70
    return( ord( substr( ${ $self->[FIRST2] }, 0, 1 ) & "\x70" ) >> 4 );
}

my $rsv;
sub set_rsv {
    $rsv = $_[1];

    #Consider the first byte as a vector of 4-bit segments.

    $rsv |= 8 if substr( ${ $_[0]->[FIRST2] }, 0, 1 ) & "\x80";

    vec( substr( ${ $_[0]->[FIRST2] }, 0, 1 ), 1, 4 ) = $rsv;

    return $_[0];
}

sub set_rsv1 {
    ${ $_[0][FIRST2] } |= _RSV1();

    return $_[0];
}

sub set_rsv2 {
    ${ $_[0][FIRST2] } |= _RSV2();

    return $_[0];
}

sub set_rsv3 {
    ${ $_[0][FIRST2] } |= _RSV3();

    return $_[0];
}

sub has_rsv1 {
    return ("\0" ne (${ $_[0][FIRST2] } & _RSV1()));
}

sub has_rsv2 {
    return ("\0" ne (${ $_[0][FIRST2] } & _RSV2()));
}

sub has_rsv3 {
    return ("\0" ne (${ $_[0][FIRST2] } & _RSV3()));
}

#pre-0.064 compatibility
sub is_control_frame { return $_[0]->is_control() }

#----------------------------------------------------------------------

sub _validate_mask {
    my ($bytes) = @_;

    if (length $bytes) {
        if (4 != length $bytes) {
            my $len = length $bytes;
            die "Mask must be 4 bytes long, not $len ($bytes)!";
        }
    }

    return;
}

sub _activate_highest_bit {
    my ($self, $sr, $offset) = @_;

    substr( $$sr, $offset, 1 ) = chr( 0x80 | ord substr( $$sr, $offset, 1 ) );

    return;
}

sub _deactivate_highest_bit {
    my ($sr, $offset) = @_;

    substr( $$sr, $offset, 1 ) = chr( 0x7f & ord substr( $$sr, $offset, 1 ) );

    return;
}

1;
