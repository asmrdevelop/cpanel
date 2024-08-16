package Whostmgr::Transfers::MysqlStream;

# cpanel - Whostmgr/Transfers/MysqlStream.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::MysqlStream

=head1 DESCRIPTION

This module normalizes logic for MySQL streaming.

=head1 CONSTANTS

=head2 C<MINIMUM_CP_VERSION>

The minimum cPanel & WHM version to send or receive a MysqlDump stream
for an account transfer. (NB: C<MysqlDump> is older than its integration
into account transfers.)

=cut

use constant MINIMUM_CP_VERSION => 87;

1;
