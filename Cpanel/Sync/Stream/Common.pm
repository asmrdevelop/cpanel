package Cpanel::Sync::Stream::Common;

# cpanel - Cpanel/Sync/Stream/Common.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use base 'Cpanel::Sync::Stream';

sub send_shutdown {
    my ($self) = @_;

    return $self->_send_packet( { 'type' => 'send_shutdown', 'disconnect' => 1 } );
}

sub send_unknown {
    my ( $self, $packet ) = @_;

    return $self->_send_packet( { 'type' => 'unknown_command', 'command' => $packet->{'type'} } );
}
1;
