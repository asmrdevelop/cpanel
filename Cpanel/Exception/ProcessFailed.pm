package Cpanel::Exception::ProcessFailed;

# cpanel - Cpanel/Exception/ProcessFailed.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# A base class only, meant to reduce logic duplication.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception );

#Arbitrary limit on the amount of spewage we get.
my $MAX_STREAM_SPEWAGE_SIZE = 10_000;

sub _spew {
    my ($self) = @_;

    return join(
        "\n",
        length( $self->get('stdout') ) ? sprintf( "STDOUT: %s\n", substr( $self->get('stdout'), 0, $MAX_STREAM_SPEWAGE_SIZE ) ) : (),
        length( $self->get('stderr') ) ? sprintf( "STDERR: %s\n", substr( $self->get('stderr'), 0, $MAX_STREAM_SPEWAGE_SIZE ) ) : (),
        $self->SUPER::_spew(),
    );
}

1;
