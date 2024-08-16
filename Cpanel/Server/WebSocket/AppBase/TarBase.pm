package Cpanel::Server::WebSocket::AppBase::TarBase;

# cpanel - Cpanel/Server/WebSocket/AppBase/TarBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::AppBase::TarBase

=head1 DESCRIPTION

This class allows a cPanel or WHM user to transfer files via tar over WebSocket.
It subclasses L<Cpanel::Server::WebSocket::AppBase::Streamer> and implements
that module’s required C<run()> method. It expects the concrete class to
create:

=over

=item * the C<_STREAMER()> constant/subroutine

=item * a C<_streamer_args> array ref as an internal property of the instance

=back

=head1 INTERFACE

=head2 I/O

See L<Cpanel::Streamer::TarBackup>. All WebSocket data messages are
sent as binary.

=head2 Close Codes

If L<tar(1)> exits nonzero, that exit code is added to 4,000, and that sum
is given as the WebSocket close code. For example, if C<tar> exits 2, the
WebSocket close code will be 4002. Any other failures are reported as
internal errors (code 1011).

=cut

use parent qw(
  Cpanel::Server::WebSocket::AppBase::Streamer
);

use constant {
    _FRAME_CLASS => 'Net::WebSocket::Frame::binary',

    # One day should be enough for anything reasonable … right??
    TIMEOUT => 86400,

    # cf. Net::WebSocket::Frame::close
    WS_INTERNAL_ERROR => 'INTERNAL_ERROR',
};

=head1 METHODS

=head2 I<OBJ>->run( $COURIER )

See L<Cpanel::Server::Handlers::WebSocket>.

=cut

sub run {
    my ( $self, $courier ) = @_;

    return $self->SUPER::run(
        $courier,
        @{ $self->{'_streamer_args'} },
    );
}

sub _CHILD_ERROR_TO_WEBSOCKET_CLOSE ( $self, $child_error ) {
    my $exit_code = $child_error >> 8;

    # Report signals and non-tar error states as internal errors.
    if ( $child_error < 200 || $exit_code == $self->_STREAMER()->PRE_EXEC_EXIT_CODE() ) {
        return WS_INTERNAL_ERROR;
    }

    return 4000 + $exit_code;
}

1;
