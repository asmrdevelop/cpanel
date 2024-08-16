package Cpanel::Server::CpXfer;

# cpanel - Cpanel/Server/CpXfer.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::CpXfer - Base class for cpsrvd “CpXfer” modules

=head1 DESCRIPTION

See below for a description of CpXfer and how to
write its application modules.

=cut

#----------------------------------------------------------------------

=head1 SUBCLASS INTERFACE

See L</HOW TO WRITE CPXFER MODULES> below.

=head1 CLASS METHODS

=head2 I<CLASS>->run( $SERVER_OBJ, \%ARGS )

Runs the module/application. $SERVER_OBJ is an instance of L<Cpanel::Server>,
and %ARGS is a hash of arguments. (See L<Cpanel::Server::Handlers::CpXfer>
for details on how cpsrvd parses CpXfer arguments.)

=cut

sub run {
    my ( $class, $server_obj, $args_hr ) = @_;

    my $self = bless { _server => $server_obj }, $class;

    $self->_BEFORE_HEADERS($args_hr);

    $self->_print_headers();

    $self->_AFTER_HEADERS($args_hr);

    return;
}

#----------------------------------------------------------------------

=head1 INSTANCE METHODS

Since this class is not instantiated externally, these methods are
only useful from within the subclass interface.

=head2 I<OBJ>->get_server_obj()

Gives the L<Cpanel::Server> instance that was given to C<run()>.

=cut

sub get_server_obj {
    return $_[0]->{'_server'};
}

=head2 I<OBJ>->get_socket()

A convenience method that gives the client socket.
(This is also obtainable, with a bit more work,
via the object that C<get_server_obj()> returns.)

=cut

sub get_socket {
    return $_[0]->get_server_obj()->connection()->get_socket();
}

#----------------------------------------------------------------------

# NB: The actual Content-Type doesn’t appear to matter to callers,
# but this is the pattern that was in use prior to the creation of this
# base class.
#
sub _content_type {
    my ($self) = @_;

    my $type = ref $self;
    substr( $type, 0, 1 + rindex( $type, ':' ) ) = q<>;

    return "cpanel/$type";
}

sub _print_headers {
    my ($self) = @_;

    my $server_obj = $self->{'_server'};

    my $content_type = $self->_content_type();

    print { $self->get_socket() } "HTTP/1.1 200 OK\r\nContent-type: $content_type\r\nConnection: close\r\n\r\n" or $server_obj->check_pipehandler_globals();

    $server_obj->sent_headers_to_socket();

    return;
}

#----------------------------------------------------------------------

=head1 HOW TO WRITE CPXFER MODULES

Modules reside in application specific namespaces, e.g.
L<Cpanel::Server::CpXfer::cpanel::MyApp>. (See
C<Cpanel::App::get_normalized_name()> for the application names used
in namespaces.)

Each module must define the following methods:

=over

=item * C<verify_access()> - See L<Cpanel::Server::Handlers::Modular>
for an explantion of this method. (NB: L<Cpanel::Server::Handlers::CpXfer>
is what calls this method; that’s why it’s named as “public”.)

=item * C<_BEFORE_HEADERS($ARGS_HR)> - Logic to implement before the
success HTTP headers are sent. You can fail the request by throwing an
appropriate exception (e.g., a L<Cpanel::Exception::cpsrvd> subclass
instance).

This method receives a hash reference of arguments.
These arguments come from L<Cpanel::Server::Handlers::CpXfer>.

=item * C<_AFTER_HEADERS($ARGS_HR)> - The “meat” of your module;
this is called after the (success) HTTP response headers are sent.

=back

=head1 CPXFER PROTOCOL DESCRIPTION

CpXfer is a “quick-and-dirty” protocol that combines the bidirectional
power of WebSocket with the simplicity of ordinary HTTP.

CpXfer begins with an ordinary HTTP GET request. The response is a standard
HTTP/1.1 response that always includes C<Connection: close> as one of the
headers.

Once a successful response header is sent, the client and server use the
TCP connection “normally”. (HTTP failure responses should be treated as
normal HTTP failures are.)

=head2 Major differences with WebSocket

CpXfer lacks the following WebSocket features:

=over

=item * message boundary preservation

=item * ability to be proxied

=item * protocol-level shutdown (i.e., close frames)

=item * protocol-level keep-alive (i.e., ping/pong)

=item * protocol-level compression

=item * standardization

=back

Due to the lack of standardization, cpsrvd is the only CpXfer server
implementation, and cPanel & WHM contains the only client implementations.
Moreover, CpXfer applications are not called within cpsrvd sessions;
they only make sense when authenticated via API token (or the old WHM
access hashes).

CpXfer’s advantages over WebSocket are:

=over

=item * Its simplicity allows applications to treat CpXfer connections
as ordinary sockets—because after the handshake that’s all they are!

=item * Because the protocol consists of little more than HTTP header
parsing, CpXfer is lighter than WebSocket. An application doesn’t need
to implement any framing logic (beyond TCP’s and TLS’s, which the kernel
and L<IO::Socket::SSL> handle for us), and the protocol itself is a bit
lighter because of the absence of framing bytes.

=back

=head1 SEE ALSO

See the Cpanel::Server::xfer* modules for CpXfer implementations
that predate this base class.

L<Cpanel::CpXferClient> implements client logic for this protocol.

=cut

1;
