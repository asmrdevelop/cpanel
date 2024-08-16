package Cpanel::Server::ModularApp;

# cpanel - Cpanel/Server/ModularApp.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::ModularApp

=head1 DESCRIPTION

This is a base class that implements the C<verify_access()> method
that L<Cpanel::Server::Handlers::Modular> expects to find in each
application module that it loads.

Ordinarily you won’t inherit from this module directly, but from a
subclass of it.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 SUBCLASS INTERFACE

=head2 I<CLASS>->_can_access( $SERVER_OBJ )

C<verify_access()> checks this to determine whether the request should
have access to the loaded module. It should return a simple boolean; a
falsey return prompts an HTTP “Forbidden” response.

$SERVER_OBJ is an instance of L<Cpanel::Server>.

This is normally provided by a service-specific intermediate class
(e.g., L<Cpanel::Server::ModularApp::cpanel>) rather than by actual
application modules.

=cut

=head1 PUBLIC OVERRIDABLE METHODS

=head2 I<CLASS>->verify_access( SERVER_OBJ )

L<Cpanel::Server::Handlers::Modular> calls this method after loading this
module. See that module for the description of this interface.

=cut

sub verify_access {
    my ( $self, $server_obj ) = @_;

    # This is implemented by the service-specific intermediate class
    # (e.g., Cpanel::Server::SSE::whostmgr).
    if ( !$self->_can_access($server_obj) ) {
        die Cpanel::Exception::create('cpsrvd::Forbidden');
    }

    return 1;
}

1;
