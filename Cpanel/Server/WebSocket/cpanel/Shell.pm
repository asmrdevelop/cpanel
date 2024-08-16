package Cpanel::Server::WebSocket::cpanel::Shell;

# cpanel - Cpanel/Server/WebSocket/cpanel/Shell.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::cpanel::Shell

=head1 DESCRIPTION

WebSocket shell/terminal implementation for cPanel.

This module inherits from L<Cpanel::Server::WebSocket::AppBase::Shell>
and L<Cpanel::Server::WebSocket::cpanel>.

=cut

use parent qw(
  Cpanel::Server::WebSocket::AppBase::Shell
  Cpanel::Server::WebSocket::cpanel
);

use Cpanel::Server::Type::Role::FileStorage ();

use constant _ACCEPTED_FEATURES => ('ssh');

sub _can_access ( $class, $server_obj ) {
    return $class->SUPER::_can_access($server_obj) && do {
        Cpanel::Server::Type::Role::FileStorage->is_enabled();
    };
}

1;
