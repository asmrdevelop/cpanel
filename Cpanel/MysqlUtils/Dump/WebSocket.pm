package Cpanel::MysqlUtils::Dump::WebSocket;

# cpanel - Cpanel/MysqlUtils/Dump/WebSocket.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::MysqlUtils::Dump::WebSocket

=head1 DESCRIPTION

Logic for the intersection between L<Cpanel::MysqlUtils::Dump>
and its cpsrvd WebSocket frontend.

=head1 CONSTANTS

=head2 C<COLLATION_ERROR_CLOSE_STATUS>

The WebSocket status sent on a MySQL collation error.

=cut

use constant COLLATION_ERROR_CLOSE_STATUS => 4000;

1;
