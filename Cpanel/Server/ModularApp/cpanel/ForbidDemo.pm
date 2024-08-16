package Cpanel::Server::ModularApp::cpanel::ForbidDemo;

# cpanel - Cpanel/Server/ModularApp/cpanel/ForbidDemo.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::ModularApp::cpanel::ForbidDemo

=head1 SYNOPSIS

    use parent 'Cpanel::Server::ModularApp::cpanel::ForbidDemo';

=head1 DESCRIPTION

This module implements a C<verify_access()> method that allows access
for cPanel users except demo-mode users.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->verify_access( $SERVER_OBJ )

Satisfies the framework requirement.

=cut

sub verify_access {
    my ( $self, $server_obj ) = @_;
    my $auth = $server_obj->auth();

    if ( $auth->get_demo() ) {
        die Cpanel::Exception::create( 'cpsrvd::Forbidden', 'This resource is unavailable in demo mode.' );
    }

    return 1;
}

1;
