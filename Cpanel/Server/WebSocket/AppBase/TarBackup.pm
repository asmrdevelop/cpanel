package Cpanel::Server::WebSocket::AppBase::TarBackup;

# cpanel - Cpanel/Server/WebSocket/AppBase/TarBackup.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::AppBase::TarBackup

=head1 DESCRIPTION

This class implements an end class for
L<Cpanel::Server::WebSocket::AppBase::TarBase> that provides “upload”
functionality.

=head1 INTERFACE

See the base class for more information.

=head2 I/O

See L<Cpanel::Streamer::TarBackup>. All WebSocket messages are
sent as binary.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Server::WebSocket::AppBase::TarBase
);

use constant {

    _STREAMER => 'Cpanel::Streamer::TarBackup',
};

1;
