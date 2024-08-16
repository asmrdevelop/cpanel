package Cpanel::Server::WebSocket::App::Shell::WHMDisable;

# cpanel - Cpanel/Server/WebSocket/App/Shell/WHMDisable.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::App::Shell::WHMDisable

=head1 SYNOPSIS

See the base class.

=head1 DESCRIPTION

This subclasses L<Cpanel::Config::TouchFileBase> to implement a touch file
to disable the Terminal UI in WHM. This disabling will apply even for root.

=cut

use parent qw( Cpanel::Config::TouchFileBase );

use constant _TOUCH_FILE => '/var/cpanel/disable_whm_terminal_ui';

1;
