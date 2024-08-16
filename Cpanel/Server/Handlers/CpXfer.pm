package Cpanel::Server::Handlers::CpXfer;

# cpanel - Cpanel/Server/Handlers/CpXfer.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::CpXfer - CpXfer handler for cpsrvd

=head1 SYNOPSIS

    # This is how this class is normally instantiated.
    my $handler_obj = $server_obj->get_handler('CpXfer');

=head1 DESCRIPTION

This module interfaces with cpsrvd to call CpXfer modules as requests dictate.
It subclasses L<Cpanel::Server::Handler> and implements the module-loading
behavior described in L<Cpanel::Server::Handlers::Modular>.

See L<Cpanel::Server::CpXfer> for more information about CpXfer and
how to create its application modules.

=cut

use parent 'Cpanel::Server::Handler';

use Cpanel::Exception                 ();
use Cpanel::Server::Handlers::Modular ();

# accessed from tests
use constant _MODULE_NS => 'Cpanel::Server::CpXfer';

=head1 METHODS

=head2 I<OBJ>->handler( $MODULE_NAME )

Calls the relevant CpXfer module (named by $MODULE_NAME).

This passes the parsed query from the HTTP request’s URL
as the arguments hashref given to the module’s C<run()> method.

=cut

sub handler {
    my ( $self, $module ) = @_;

    # There’s no need to register CpXfer processes in the session
    # because by nature CpXfer isn’t going to run in a session.
    # In fact, let’s make sure of that …
    if ( $self->get_server_obj()->get_current_session() ) {
        die Cpanel::Exception::create_raw( 'cpsrvd::BadRequest', 'CpXfer does not run in a session!' );
    }

    my $full_mod = Cpanel::Server::Handlers::Modular::load_and_authz_module( $self->get_server_obj(), _MODULE_NS(), $module );

    $full_mod->run(
        $self->get_server_obj(),
        scalar $self->get_server_obj()->timed_parseform(60),
    );

    return;
}

1;
