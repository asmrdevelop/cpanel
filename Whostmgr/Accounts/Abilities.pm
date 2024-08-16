package Whostmgr::Accounts::Abilities;

# cpanel - Whostmgr/Accounts/Abilities.pm           Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::Abilities

=head1 SYNOPSIS

    if ( Whostmgr::Accounts::Abilities::new_account_can_have_shell() ) {
        # ..
    }

    if ( Whostmgr::Accounts::Abilities::new_account_can_have_cgi() ) {
        # ..
    }

    Whostmgr::Accounts::Abilities::filter_package_by_disabled_roles(
        \%PKG,
        [ 'FileStorage' ],
    );

=head1 DESCRIPTION

This module encapsulates logic for restrictions on user abilities with
respect to enabled/disabled roles on the system.

=cut

#----------------------------------------------------------------------

use Cpanel::Server::Type::Role::FileStorage ();
use Cpanel::Server::Type::Role::WebServer   ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = new_account_can_have_shell()

Indicates whether the server can give shell access.

=cut

sub new_account_can_have_shell {
    return Cpanel::Server::Type::Role::FileStorage->is_enabled();
}

=head2 $yn = new_account_can_have_cgi()

Indicates whether the server can give CGI access.

=cut

sub new_account_can_have_cgi {
    return Cpanel::Server::Type::Role::WebServer->is_enabled();
}

=head2 filter_package_by_disabled_roles( \%PKG, \@ROLE_NAMES )

Sets elements of %PKG according to members of @ROLE_NAMES; i.e., if a
member of @ROLE_NAMES excludes the ability to have a package with a
certain configuration, that configuration is rectified.

B<NOTE:> %PKG is modified in-place.

This should only be used in limited circumstances; generally, if a
package add/modification operation requests an ability that the server
doesn’t offer, the request should fail instead of being “coerced” into
being valid.

=cut

sub filter_package_by_disabled_roles ( $pkg, $roles_ar ) {
    for my $role_name (@$roles_ar) {
        if ( $role_name eq 'WebServer' ) {
            $pkg->{'CGI'} = 'n';
        }
        elsif ( $role_name eq 'FileStorage' ) {
            $pkg->{'HASSHELL'} = 'n';
        }
    }

    return;
}

1;
