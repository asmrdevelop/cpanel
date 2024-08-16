package Cpanel::Server::Handlers::SyncStream;

# cpanel - Cpanel/Server/Handlers/SyncStream.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::PwCache              ();
use Cpanel::Sync::Stream::Server ();
use parent 'Cpanel::Server::Handler';

sub handler {
    my ($self) = @_;
    my $server_obj = $self->get_server_obj();

    local $SIG{'__DIE__'};    # Need to override cpsrvd's default handler

    my $server_socket = $server_obj->connection()->get_socket();

    print {$server_socket} "HTTP/1.1 200 OK\r\nContent-type: cpanel/syncstream\r\nConnection: close\r\n\r\n" or $server_obj->check_pipehandler_globals();
    $server_obj->sent_headers_to_socket();
    my $server = Cpanel::Sync::Stream::Server->new( 'socket' => $server_socket, 'fs_root' => Cpanel::PwCache::gethomedir() );
    while ( $server->receive_and_process_one_packet("packet_from_client") ) { }

    return 0;
}

1;
