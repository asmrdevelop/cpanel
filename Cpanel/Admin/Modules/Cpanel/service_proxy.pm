# cpanel - Cpanel/Admin/Modules/Cpanel/service_proxy.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::Admin::Modules::Cpanel::service_proxy;

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Admin::Modules::Cpanel::service_proxy

=head1 DESCRIPTION

This module contains privilege-escalation logic for user code that needs
to manipulate service proxying.

=cut

use parent qw( Cpanel::Admin::Base );

use constant _actions => (
    'GET_SERVICE_PROXY_BACKENDS',
    'SET_SERVICE_PROXY_BACKENDS',
    'UNSET_ALL_SERVICE_PROXY_BACKENDS',
);

=head1 FUNCTIONS

=head2 GET_SERVICE_PROXY_BACKENDS()

A wrapper around L<Cpanel::AccountProxy::Storage>’s C<get_service_proxy_backends_for_user> that
retrieves the service proxy backends for the calling user.

=cut

sub GET_SERVICE_PROXY_BACKENDS ($self) {

    my $username = $self->get_caller_username();

    require Cpanel::AccountProxy::Storage;
    return Cpanel::AccountProxy::Storage::get_service_proxy_backends_for_user($username);
}

=head2 SET_SERVICE_PROXY_BACKENDS( %BACKENDS )

A wrapper around L<Cpanel::AccountProxy::Transaction>’s C<set_backends_and_update_services> that
sets the service proxy backends for the calling user.

=cut

sub SET_SERVICE_PROXY_BACKENDS ( $self, %backends ) {

    my $username = $self->get_caller_username();

    my @types = keys %backends;

    if ( keys %{ $backends{worker} } ) {
        require Cpanel::AccountProxy::Storage;
        Cpanel::AccountProxy::Storage::validate_proxy_backend_types_or_die( [ keys %{ $backends{worker} } ] );
    }

    # Ensure the username parameter to be passed is the caller's username
    $backends{username} = $username;

    require Cpanel::AccountProxy::Transaction;
    Cpanel::AccountProxy::Transaction::set_backends_and_update_services(
        %backends,
    );

    return;
}

=head2 UNSET_ALL_SERVICE_PROXY_BACKENDS()

A wrapper around L<Cpanel::AccountProxy::Transaction>’s C<unset_all_backends_and_update_services> that
unsets all the service proxy backends for the calling user.

=cut

sub UNSET_ALL_SERVICE_PROXY_BACKENDS ($self) {

    my $username = $self->get_caller_username();

    require Cpanel::AccountProxy::Transaction;
    Cpanel::AccountProxy::Transaction::unset_all_backends_and_update_services($username);

    return;
}

1;
