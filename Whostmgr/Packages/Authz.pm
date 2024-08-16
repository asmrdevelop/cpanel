package Whostmgr::Packages::Authz;

# cpanel - Whostmgr/Packages/Authz.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Packages::Authz

=head1 SYNOPSIS

    my $can_access = current_reseller_can_use_package( 'greatstuff' );

=head1 DESCRIPTION

This module contains logic to authorize a reseller to access a given package.

=cut

#----------------------------------------------------------------------

use Whostmgr::ACLS ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = current_reseller_can_use_package( $PACKAGENAME )

This function queries the state of various process globals to determine
if the caller has permission to use a package named by $PACKAGENAME.

Note that behavior is B<undefined> in the case of nonexistent packages.
It is assumed for now that the caller ensures the package’s existence
independently; obviously, if the package is nonexistent, then that overrides
this function’s return.

It returns truthy if the reseller can access the package, falsy otherwise.

=cut

sub current_reseller_can_use_package ($packagename) {
    return ( 0 == rindex( $packagename, "$ENV{'REMOTE_USER'}_", 0 ) ) || Whostmgr::ACLS::hasroot() ? 1 : 0;
}

1;
