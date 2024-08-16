package Cpanel::Server::SSE::whostmgr;

# cpanel - Cpanel/Server/SSE/whostmgr.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::SSE::whostmgr - Base class for WHM SSE modules

=head1 SYNOPSIS

    use parent qw( Cpanel::Server::SSE::whostmgr );

    # defaults to root-only
    use constant _ACCEPTED_ACLS => ( 'list-pkgs' );

    sub _run {
        my ($self) = @_;

        $self->_send_sse_heartbeat();

        $self->_send_sse_message(@opts);

        ...;
    }

=cut

use parent qw(
  Cpanel::Server::SSE
  Cpanel::Server::ModularApp::whostmgr
);

1;
