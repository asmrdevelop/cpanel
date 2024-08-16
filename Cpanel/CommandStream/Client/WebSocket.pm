package Cpanel::CommandStream::Client::WebSocket;

# cpanel - Cpanel/CommandStream/Client/WebSocket.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::WebSocket

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This class consists of a public interface for
L<Cpanel::CommandStream::Client::WebSocket::Base>.
Because it doesn’t provide authentication it is B<not> an end class;
see subclasses of L<Cpanel::CommandStream::Client::WebSocket::Base> for
that.

=cut

#----------------------------------------------------------------------

use Cpanel::CommandStream::Client::Response::exec ();

#----------------------------------------------------------------------

=head1 METHODS

See the base class for additional public methods.

=head2 promise($request) = I<OBJ>->request( $NAME, @ARGUMENTS )

Wraps L<Cpanel::CommandStream::Client::Requestor>’s C<request()>
method. Returns a promise to the response from that method (which
should be an object in the C<Cpanel::CommandStream::Client::Request::>
namespace).

=cut

sub request ( $self, $name, @args ) {
    return $self->_Get_requestor_p()->then(
        sub ($requestor) {
            return $requestor->request( $name, @args );
        },
    );
}

=head2 promise($exec_result) = I<OBJ>->exec(%OPTS)

A convenience wrapper around C<request()> (above) that runs an C<exec>
request on the remote server and gives the result as a
L<Cpanel::CommandStream::Client::Response::exec> instance.

This doesn’t make the output available as it arrives, but only at the end.
If you need in-progress streamed output then call C<request('exec', ...)>
instead.

%OPTS are:

=over

=item * C<command> - array ref of program to run and args

=back

The returned promise resolves to a
L<Cpanel::CommandStream::Client::Response::exec> instance.

=cut

sub exec ( $self, %opts ) {
    my ( $stdout, $stderr ) = ( q<>, q<> );

    return $self->_Exec(
        %opts{'command'},

        stdout => sub { $stdout .= shift },
        stderr => sub { $stderr .= shift },
    )->then(
        sub ($errstatus) {
            return Cpanel::CommandStream::Client::Response::exec->new(
                program => $opts{'command'}[0],
                status  => $errstatus,
                stdout  => $stdout,
                stderr  => $stderr,
            );
        },
    );
}

1;
