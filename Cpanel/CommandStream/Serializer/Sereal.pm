package Cpanel::CommandStream::Serializer::Sereal;

# cpanel - Cpanel/CommandStream/Serializer/Sereal.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Serializer::Sereal - L<Sereal> for CommandStream

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::CommandStream::Serializer';

use Cpanel::Sereal::Decoder ();
use Cpanel::Sereal::Encoder ();

#----------------------------------------------------------------------

sub _serialize ( $self, $struct ) {
    return ( $self->{'_encoder'} ||= Cpanel::Sereal::Encoder::create() )->encode($struct);
}

sub _deserialize ( $self, $buf_sr ) {
    return ( $self->{'_decoder'} ||= Cpanel::Sereal::Decoder::create() )->decode($$buf_sr);
}

1;
