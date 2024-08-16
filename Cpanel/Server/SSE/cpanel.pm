package Cpanel::Server::SSE::cpanel;

# cpanel - Cpanel/Server/SSE/cpanel.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::SSE::cpanel

=head1 SYNOPSIS

    use parent qw( Cpanel::Server::SSE::cpanel );

    # defaults to off
    use constant _ALLOW_DEMO_MODE => 1;

    # defaults to no access for anyone
    use constant _ACCEPTED_FEATURES => ( .. );

    sub _run {
        my ($self) = @_;

        $self->_send_sse_heartbeat();

        $self->_send_sse_message(@opts);

        ...;
    }

=cut

use parent qw(
  Cpanel::Server::SSE
  Cpanel::Server::ModularApp::cpanel
);

1;
