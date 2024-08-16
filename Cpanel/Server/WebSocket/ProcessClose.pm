package Cpanel::Server::WebSocket::ProcessClose;

# cpanel - Cpanel/Server/WebSocket/ProcessClose.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::ProcessClose

=head1 DESCRIPTION

This module contains logic for the interface between a process’s
end and WebSocket close status.

=head1 FUNCTIONS

=head2 ($code, $reason) = child_error_to_code_and_reason( $CHILD_ERROR )

This function serves the use case where a process’s exit status will
be fully exposed to the WebSocket peer. This isn’t ordinarily what’s
desirable; normally we want to abstract details of system internals
like processes. The use case for this logic is applications like
a remote terminal, where the nature of the application itself concerns
a server process.

Input is the Perl $CHILD_ERROR (aka C<$?>).
Outputs are the code and reason to feed into
L<Net::WebSocket::Frame::close>’s constructor; see that module for
definitions of those values.

=cut

sub child_error_to_code_and_reason {
    my ($child_error) = @_;

    local $@;

    my $msg = eval {
        require Cpanel::ChildErrorStringifier;
        my $err_str = Cpanel::ChildErrorStringifier->new(
            $child_error,
        );

        my $err_code = $err_str->error_code();
        my $sig_name = $child_error && !$err_code && $err_str->signal_name();

        sprintf(
            q<{"got_signal":%s,"result":%s,"dumped_core":%s}>,
            $sig_name ? 'true' : 'false',
            ( $sig_name               ? qq<"$sig_name"> : $err_code || 0 ),
            ( $err_str->dumped_core() ? 'true'          : 'false' ),
        );
    };

    warn if !$msg;

    return ( 'INTERNAL_ERROR', $msg // "CHILD_ERROR: $child_error" );
}

1;
