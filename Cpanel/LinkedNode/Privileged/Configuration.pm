package Cpanel::LinkedNode::Privileged::Configuration;

# cpanel - Cpanel/LinkedNode/Privileged/Configuration.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

my @_GETTERS;

BEGIN {
    @_GETTERS = (
        'alias',
        'hostname',
        'username',
        'api_token',
        'enabled_services',
        'worker_capabilities',
        'last_check',
        'version',
        'tls_verified',
        'system_settings',
    );
}

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Privileged::Configuration

=head1 DESCRIPTION

This module represents a linked node configuration as
a privileged user sees it.

See L<Cpanel::LinkedNode::User::Configuration> for the equivalent logic
for an unprivileged user.

=cut

#----------------------------------------------------------------------

use Cpanel::Context    ();
use Cpanel::LoadModule ();

#----------------------------------------------------------------------

=head1 CONSTRUCTOR

=head2 I<CLASS>->new( %OPTS )

%OPTS should contain:

=over

=item * C<alias> - The remote node’s alias

=item * C<hostname> - The remote node’s hostname

=item * C<username> - The username used when connecting to the remote node

=item * C<api_token> - The API token used when connecting to the remote node

=item * C<enabled_services> - An ARRAYREF of services that are enabled on
the remote node.

This value will not be available on non-cPanel remote nodes.

=item * C<worker_capabilities> - A HASHREF of capabilities that can be utilized
on the remote node where
the keys are the capability names and the values are HASHREFs of any
additional options required by the specific capability.

In this context, a “capability” is an abstract concept describing a
grouping of services that are required for a node to perform specific
operations. For example, a node can provide the “Mail” capability if
all of the services required to send and receive mail are enabled.

=item * C<last_check> - A UNIX timestamp indicating the last time a remote
node was queried to determine its current settings.

=item * C<version> - The current cPanel & WHM version the remote node is
running.

This value will not be available on non-cPanel remote nodes.

=item * C<tls_verified> - A boolean indicating whether or not the remote node’s
SSL certificate could be verified.

=back

=head1 ACCESSORS

This class exposes accessors for each of the constructor’s arguments.
Additionally, this also exposes:

=over

=item * C<allow_bad_tls()> - The inverse of C<tls_verified()>, provided
as a convenience for parity with L<Cpanel::LinkedNode::User::Configuration>.

=back

=cut

use Class::XSAccessor (
    constructor => 'new',
    getters     => \@_GETTERS,
);

#----------------------------------------------------------------------

# Documented above
sub allow_bad_tls ($self) {
    return !$self->tls_verified();
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 $api_obj = I<OBJ>->get_async_remote_api()

Returns a L<Cpanel::Async::RemoteAPI::WHM> instance for the I<OBJ>.
This instance is cached inside the I<OBJ>, so subsequent calls will
return the same object.

=cut

sub get_async_remote_api ($self) {
    return $self->_get_remote_api('Cpanel::Async::RemoteAPI::WHM::ToChild');
}

sub _get_remote_api ( $self, $class ) {
    Cpanel::LoadModule::load_perl_module($class);

    return $self->{"_remote_api_$class"} ||= do {
        my $obj = $class->new_from_token( $self->hostname(), $self->username(), $self->api_token() );

        $obj->disable_tls_verify() if $self->allow_bad_tls();

        $obj;
    };
}

#----------------------------------------------------------------------

=head2 $api_obj = I<OBJ>->get_remote_api()

Like C<get_async_remote_api()> but
returns a L<Cpanel::RemoteAPI::WHM::ToChild> instance.

=cut

sub get_remote_api ($self) {
    return $self->_get_remote_api('Cpanel::RemoteAPI::WHM::ToChild');
}

#----------------------------------------------------------------------

=head2 $cstream = I<OBJ>->get_commandstream()

Returns a L<Cpanel::CommandStream::Client::WebSocket> instance
for I<OBJ>. As with C<get_remote_api()>, the response is cached.

=cut

sub get_commandstream ($self) {
    return $self->{'_commandstream'} ||= do {

        # Use C::LM rather than require() in order to hide from perlpkg.
        # (cf. CPANEL-34963)
        Cpanel::LoadModule::load_perl_module('Cpanel::CommandStream::Client::WebSocket::APIToken');

        Cpanel::CommandStream::Client::WebSocket::APIToken->new(
            hostname         => $self->hostname(),
            username         => $self->username(),
            api_token        => $self->api_token(),
            tls_verification => $self->allow_bad_tls() ? 'off' : 'on',
        );
    };
}

#----------------------------------------------------------------------

=head2 ($name, $value) = I<OBJ>->get_api_token_header()

Returns the HTTP header name and value needed to authenticate to the
linked node using I<OBJ>’s stored username and API token.

=cut

sub get_api_token_header ($self) {
    Cpanel::Context::must_be_list();

    return (
        'Authorization',
        sprintf(
            "whm %s:%s",
            $self->username(),
            $self->api_token(),
        ),
    );
}

#----------------------------------------------------------------------

sub TO_JSON ($self) {
    my %vals = %{$self}{@_GETTERS};
    return \%vals;
}

1;
