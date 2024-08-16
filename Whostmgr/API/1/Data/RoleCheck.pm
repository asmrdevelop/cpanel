package Whostmgr::API::1::Data::RoleCheck;

# cpanel - Whostmgr/API/1/Data/RoleCheck.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Data::RoleCheck

=head1 SYNOPSIS

    verify_role_dependency( 'Whostmgr::API::1::SSL', 'disable_autossl' );

=head1 DESCRIPTION

This module implements restrictions to APIs that should
not function because of system role configuration. For example,
if the C<MySQL> role is disabled, none of the roles under the
C<RemoteMySQL> namespace should be callable.

=cut

#----------------------------------------------------------------------

use Cpanel::LoadModule ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 verify_role_dependency( $MODULE, $FUNCTION_NAME )

$MODULE is a full Perl namespace. Throws
L<Cpanel::Exception::System::RequiredRoleDisabled> if needed.

=cut

sub verify_role_dependency {
    my ( $module, $funcname ) = @_;

    my $needs_role = $module->NEEDS_ROLE();

    #----------------------------------------------------------------------
    # XXX XXX XXX
    #
    # The NEEDS_ROLE checks below are sanity checks for development.
    # They help to ensure that no one will inadvertently create a functional,
    # non-role-restricted API that should, in fact, have a role restriction.
    #
    # IMPORTANT: Do NOT change the logic below without a thorough discussion
    # among all interested development teams and other stakeholders.
    #----------------------------------------------------------------------

    if ( ref $needs_role ) {

        # We only allow undef as a role for a specific API call.
        if ( !exists $needs_role->{$funcname} ) {
            die "$module needs a NEEDS_ROLE entry for “$funcname”!";
        }

        $needs_role = $needs_role->{$funcname};
    }
    elsif ( !$needs_role ) {
        die "Module-level NEEDS_ROLE must give a role, not undef!";
    }

    if ( ref $needs_role ) {
        require Cpanel::Server::Type::Profile::Roles;
        Cpanel::Server::Type::Profile::Roles::verify_roles_enabled($needs_role);
    }
    elsif ($needs_role) {
        Cpanel::LoadModule::load_perl_module("Cpanel::Server::Type::Role::$needs_role")->verify_enabled();
    }

    return 1;
}

1;
