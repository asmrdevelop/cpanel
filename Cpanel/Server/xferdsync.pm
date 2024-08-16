package Cpanel::Server::xferdsync;

# cpanel - Cpanel/Server/xferdsync.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Dsync::Stream ();

#Arguments are:
#   - a Cpanel::Server instance
#   - a valid email_account
#
#This either returns 0 or bugs out with the C::Server instance.
#
sub do_acctxferdsync_to_socket ( $server_obj, $email_account ) {

    my $socket = $server_obj->connection->get_socket();

    $server_obj->internal_error("The email_account passed to xferdsync is invalid") if !$email_account;

    print {$socket} "HTTP/1.1 200 OK\r\nContent-type: cpanel/acctxferdsync\r\nConnection: close\r\n\r\n" or $server_obj->check_pipehandler_globals();
    $server_obj->sent_headers_to_socket();

    Cpanel::Dsync::Stream::connect( $socket, $email_account );

    return 0;
}

1;
