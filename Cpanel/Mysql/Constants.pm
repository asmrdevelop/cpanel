package Cpanel::Mysql::Constants;

# cpanel - Cpanel/Mysql/Constants.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Mysql::Constants

=head1 DESCRIPTION

This module houses constants that are useful for working with MySQL.

=head1 CONSTANTS

=head2 DEFAULT_UNIX_SOCKET_NAME()

The filename of MySQL’s default UNIX socket.

=head2 DEFAULT()

A reference to a hash of default F<my.cnf> values. See the code
for the contents.

=cut

use constant {
    DEFAULT_UNIX_SOCKET_NAME => 'mysql.sock',

    # Keys are named for actual MySQL options.
    DEFAULT => {
        datadir => '/var/lib/mysql',    # on Linux RPMs, anyway
        port    => 3306,
    },

    # 1024MB ensures the client is always at least as large as the server limit.
    # The actual limit is MIN(max_allowed_packet_server, max_allowed_packet_client).
    MAX_ALLOWED_PACKET => '1024MB',
};

1;
