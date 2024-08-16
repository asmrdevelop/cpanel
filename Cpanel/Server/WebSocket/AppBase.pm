package Cpanel::Server::WebSocket::AppBase;

# cpanel - Cpanel/Server/WebSocket/AppBase.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::AppBase

=head1 DESCRIPTION

Ancestor class for all cpsrvd WebSocket endpoints.

B<DON’T> extend this class directly if all you want to do is create a
cpsrvd WebSocket endpoint; see L<Cpanel::Server::Handlers::WebSocket>
for instructions on how to do that.

=cut

#----------------------------------------------------------------------

# Use Net::WebSocket::Endpoint’s default:
use constant _MAX_PINGS => undef;

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->MAX_PINGS()

A public accessor for C<_MAX_PINGS>; see
L<Cpanel::Server::Handlers::WebSocket>.

=cut

sub MAX_PINGS ($self) {
    return $self->_MAX_PINGS();
}

1;
