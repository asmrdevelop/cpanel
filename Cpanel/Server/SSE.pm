package Cpanel::Server::SSE;

# cpanel - Cpanel/Server/SSE.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::SSE - Base class for cpsrvd SSE modules

=head1 SYNOPSIS

See the service-specific subclasses (e.g., L<Cpanel::Server::SSE::cpanel>)
for demos of how to create SSE modules.

B<NOTE:> To pass arguments to SSE modules, use URL query strings.
(NB: L<Cpanel::Form> stores parsed query strings.)

=head1 DESCRIPTION

This base class contains logic that’s generally useful for SSE modules.

=cut

use parent qw( Cpanel::Server::ModularApp );

use Cpanel::Server::Responder ();
use HTTP::ServerEvent         ();

use Cpanel::Locale::Lazy 'lh';

=head1 PUBLIC METHODS

=head2 I<CLASS>->new( %OPTS )

%OPTS are:

=over

=item * C<responder> - An instance of L<Cpanel::Server::Responder::Stream>.

=item * C<last_event_id> - Optional. The value of the HTTP C<Last-Event-Id>
header, if given.

=back

=cut

sub new {
    my ( $class, %opts ) = @_;

    for my $key (qw( responder )) {
        $opts{"_$key"} = delete $opts{$key} or die "Need “$key”";
    }

    # optional
    $opts{'_last_event_id'} = delete $opts{'last_event_id'};
    $opts{"_args"}          = delete $opts{'args'} || [];

    #What Cpanel::Server::Responder calls “input buffer” is actually
    #a buffer for the output stream here.
    $opts{'_output_buffer'} = $opts{'_responder'}->get_input_buffer();

    my $self = bless \%opts, $class;

    $self->_init();

    return $self;
}

=head2 I<OBJ>->run()

L<Cpanel::Server::Handlers::SSE> calls this after sending the HTTP response
headers (assuming C<has_content()> returns truthy).
C<run()> communicates with the client via the protected methods below.
It receives no arguments, and its return is ignored.

=cut

sub run {
    my ($self) = @_;

    return $self->_run();
}

#----------------------------------------------------------------------

=head1 SUBCLASS INTERFACE

In addition to the interface described in L<Cpanel::Server::ModularApp>:

=head2 I<OBJ>->_run()

Each subclass must provide a C<_run()> method, which is the real work behind
the C<run()> method.

=cut

=head2 I<OBJ>->_init()

Optional, runs at the end of C<new()>.

=cut

use constant _init => ();

#----------------------------------------------------------------------

=head1 PUBLIC OVERRIDABLE METHODS

In addition to those described in L<Cpanel::Server::ModularApp>:

=head2 I<OBJ>->has_content()

This defaults to 1, but subclasses can override it. If this returns
falsey, then C<run()> is not called, and the client is told to stop
reconnecting.

=cut

use constant has_content => 1;

#----------------------------------------------------------------------

=head1 PROTECTED METHODS

These methods are meant to be called from application modules.

=head2 I<OBJ>->_get_last_event_id()

Returns the value of the C<Last-Event-ID> HTTP header that the client
submitted (or undef if the client didn’t submit this header).

=cut

sub _get_last_event_id {
    my ($self) = @_;

    return $self->{'_last_event_id'};
}

=head2 I<OBJ>->_send_sse_heartbeat()

This sends an SSE “heartbeat” so that the client knows the connection
is still active. If a message isn’t sent for C<_HEARTBEAT_TIMEOUT()>
seconds, you should send a heartbeat.

=cut

#https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events/Using_server-sent_events#Event_stream_format
sub _send_sse_heartbeat {
    my ($self) = @_;

    $self->__responder_write(":\x0d\x0a");

    return;
}

=head2 I<OBJ>->_send_sse_message( @OPTS_KV )

This sends an SSE message. @OPTS_KV is a list of key/value pairs as
parsed by L<HTTP::ServerEvent>’s C<as_string()> method.

=cut

sub _send_sse_message {
    my ( $self, @opts_kv ) = @_;

    $self->__responder_write( HTTP::ServerEvent->as_string(@opts_kv) );

    return;
}

=head2 I<OBJ>->_get_args()

Returns the ARRAYREF of path parts following the module in the url.

Example:  ./sse/<module>/<arg1>/<arg2>/.../<argn>

would result in:

[
    'arg1',
    'arg2',
    ...
    'argn',
]

It is up to the specific Cpanel::Server::SSE sub-class to decide how
to use these.

=cut

sub _get_args {
    my ($self) = @_;
    return $self->{_args};
}

#----------------------------------------------------------------------

sub __responder_write {
    my ( $self, $content ) = @_;

    ${ $self->{'_output_buffer'} } .= $content;

    $self->{'_responder'}->write($Cpanel::Server::Responder::WRITE_NOW);

    if ( $self->{'_responder'}->can('flush_sync') ) {
        $self->{'_responder'}->flush_sync();
    }

    return;
}

1;
