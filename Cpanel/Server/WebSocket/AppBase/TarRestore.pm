package Cpanel::Server::WebSocket::AppBase::TarRestore;

# cpanel - Cpanel/Server/WebSocket/AppBase/TarRestore.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::AppBase::TarRestore

=head1 DESCRIPTION

This class implements an end class for
L<Cpanel::Server::WebSocket::AppBase::TarBase> that provides “download”
functionality.

=head1 INTERFACE

See the base class for more information.

=head2 I/O

See L<Cpanel::Streamer::TarRestore>. This expects all incoming messages
to be binary.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Server::WebSocket::AppBase::TarBase
);

use constant {

    _STREAMER => 'Cpanel::Streamer::TarRestore',
};

1;
