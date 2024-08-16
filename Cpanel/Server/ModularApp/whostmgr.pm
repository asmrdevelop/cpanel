package Cpanel::Server::ModularApp::whostmgr;

# cpanel - Cpanel/Server/ModularApp/whostmgr.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Server::ModularApp::whostmgr

=head1 DESCRIPTION

This module is analogous to L<Cpanel::Server::ModularApp::cpanel>
but for WHM applications. See that module for more details.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Server::ModularApp );

use Whostmgr::ACLS ();

#----------------------------------------------------------------------

sub _can_access ( $self, @ ) {

    my $did_init_acls;

    for my $acl ( $self->_ACCEPTED_ACLS() ) {
        return 1 if $acl eq 'any';

        if ( !$did_init_acls ) {
            Whostmgr::ACLS::init_acls();
            $did_init_acls = 1;
        }

        return 1 if Whostmgr::ACLS::checkacl($acl);
    }

    if ( !$did_init_acls ) {
        Whostmgr::ACLS::init_acls();
        return 1 if Whostmgr::ACLS::hasroot();
    }

    return 0;
}

#----------------------------------------------------------------------

=head1 SUBCLASS INTERFACE

=head2 I<OBJ>->_ACCEPTED_ACLS()

Optional, returns the list of ACLs that allow a WHM operator to run the
module.  It’s empty by default, which restricts access to root resellers.

Include C<any> as a value to allow all WHM users.

This is only relevant if the base class’s C<verify_access()> is used;
if the application overrides this method, then this method is irrelevant.

=cut

use constant _ACCEPTED_ACLS => ();

1;
