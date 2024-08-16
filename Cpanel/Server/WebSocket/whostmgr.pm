package Cpanel::Server::WebSocket::whostmgr;

# cpanel - Cpanel/Server/WebSocket/whostmgr.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::whostmgr

=head1 DESCRIPTION

This module is like L<Cpanel::Server::WebSocket::cpanel> but for WHM
WebSocket modules.

=cut

use parent qw(
  Cpanel::Server::ModularApp::whostmgr
  Cpanel::Server::WebSocket::AppBase
);

1;
