package Cpanel::Server::WebSocket::AppBase::Shell;

# cpanel - Cpanel/Server/WebSocket/AppBase/Shell.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::HTTP::QueryString ();

=encoding utf-8

=head1 NAME

Cpanel::Server::WebSocket::App::Shell - shell streamer via WebSocket for cpsrvd

=head1 SYNOPSIS

    Cpanel::Server::WebSocket::App::Shell->authorize();

    Cpanel::Server::WebSocket::App::Shell->new( $courier )->run();

=head1 DESCRIPTION

This module subclasses L<Cpanel::Server::WebSocket::AppBase::ControlStreamer>
and uses L<Cpanel::Streamer::Shell> as its streamer module.

B<IMPORTANT:> When running as the user, by convention this needs to run
with the user’s supplemental GIDs. There is logic for this in cpsrvd that
depends on the WebSocket URL for this application.

=head1 CONTROL INTERFACE

This accepts the following control messages:

=over

=item C<resize:$rows,$cols> When this arrives, we call C<set_winsize()>
on the pty with the relevant $rows and $cols.

=back

=cut

use parent qw(
  Cpanel::Server::WebSocket::AppBase::ControlStreamer
);

use Cpanel::Server::WebSocket::ProcessClose ();

use constant {
    _STREAMER    => 'Cpanel::Streamer::Shell',
    _FRAME_CLASS => 'Net::WebSocket::Frame::binary',

    #Allow the process to live indefinitely.
    TIMEOUT => 0,
};

=head1 METHODS

=head2 I<CLASS>->new( $SERVER_OBJ )

Instantiates this class. $SERVER_OBJ is an instance of
L<Cpanel::Server>.

=cut

sub new {
    my ( $class, $server_obj ) = @_;

    my $self = $class->SUPER::new();

    $self->{'_server_obj'} = $server_obj;

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->run( COURIER_OBJ )

Runs the module.

=cut

use constant _get_before_exec_cr => undef;

sub run ( $self, $courier ) {

    my $query_hr = Cpanel::HTTP::QueryString::parse_query_string_sr( \$ENV{'QUERY_STRING'} );

    return $self->SUPER::run(
        $courier,
        rows        => $query_hr->{'rows'},
        cols        => $query_hr->{'cols'},
        before_exec => $self->_get_before_exec_cr( $self->{'_server_obj'} ),
    );
}

# It’s ordinarily less than ideal to disclose system internals like
# signals and exit codes as default workflow; however, for the case
# of a shell session it’s appropriate because we expect those details
# to be relevant to the caller.
sub _CHILD_ERROR_TO_WEBSOCKET_CLOSE {
    my ( $self, $child_error ) = @_;

    return Cpanel::Server::WebSocket::ProcessClose::child_error_to_code_and_reason($child_error);
}

#NB: tested directly
sub _on_control_message {
    my ( $self, $payload ) = @_;

    my ( $type, $body ) = split m<:>, $payload, 2;

    if ( $type eq 'resize' ) {
        my ( $rows, $cols ) = split m<,>, $body;

        my $streamer = $self->get_attr('streamer');
        $streamer->get_attr('to')->set_winsize( $rows, $cols );
    }
    else {
        die "unknown control message ($payload)";
    }

    return;
}

1;
