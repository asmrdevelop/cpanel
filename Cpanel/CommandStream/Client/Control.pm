package Cpanel::CommandStream::Client::Control;

# cpanel - Cpanel/CommandStream/Client/Control.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::Control

=head1 DESCRIPTION

This class is how a CommandStream request module can tell the
L<Cpanel::CommandStream::Client> instance to stop listening on a
given request ID.

An instance of this class is given to request module handlers.
It’s not meant for use outside that context.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->forget()

Tells the creating L<Cpanel::CommandStream::Client> instance
not to listen for this object’s responses anymore.

=cut

sub forget ($self) {
    ${ $self->[0] } = 1;

    return;
}

=head2 $obj = I<CLASS>->new( $FORGOTTEN_SR, $ID )

Instantiates I<CLASS>. Normally called from
L<Cpanel::CommandStream::Client::Requestor>.

$REQUESTOR is the calling L<Cpanel::CommandStream::Client::Requestor>
instance.

=cut

sub new ( $class, $forgotten_sr ) {
    return bless [$forgotten_sr], $class;
}

1;
