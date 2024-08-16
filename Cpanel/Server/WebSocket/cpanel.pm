package Cpanel::Server::WebSocket::cpanel;

# cpanel - Cpanel/Server/WebSocket/cpanel.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::cpanel

=head1 DESCRIPTION

This module is what cPanel WebSocket modules should subclass in order
to use L<Cpanel::Server::ModularApp::cpanel>’s C<verify_access()>
implementation.

It is intended that this module may eventually implement other functionality,
so it’s better to inherit from this class than from
L<Cpanel::Server::ModularApp::cpanel> directly.

=cut

use parent qw(
  Cpanel::Server::ModularApp::cpanel
  Cpanel::Server::WebSocket::AppBase
);

1;
