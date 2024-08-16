package Whostmgr::ACLS::Reinit;

# cpanel - Whostmgr/ACLS/Reinit.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::ACLS::Reinit - Reinitialize WHM ACLs as a different user

=head1 SYNOPSIS

    use Whostmgr::ACLS::Reinit ();

    Whostmgr::ACLS::Reinit::reinitialize_as_user( $username );

=head1 DESCRIPTION

This module contains a method to reinitialize the WHM ACLs as a given user.

It must be called by a user who has root-level privileges.

=head1 METHODS

=head2 reinitialize_as_user( $username )

Reinitializes the WHM ACLs as the specified user by setting
C<$ENV{REMOTE_USER}> and calling C<Whostmgr::ACLS::clear> and
C<Whostmgr::ACLS::init>.

=over

=item Input

=over

=item C<SCALAR> - String - username

The username to reinitialize the ACLs as.

=back

=item Output

=over

This function returns nothing on success, dies otherwise.

=back

=item Throws

This function throws exceptions when:

=over

=item - The calling user does to have root-level privileges

=item - The specified username does not exist

=back

=back

=cut

sub reinitialize_as_user ($username) {

    require Whostmgr::ACLS;
    if ( !Whostmgr::ACLS::hasroot() ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create("You must have root-level privileges to reinitialize ACLs as a different user.");
    }

    require Cpanel::AcctUtils::Account;
    if ( !Cpanel::AcctUtils::Account::accountexists($username) ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'UserNotFound', [ name => $username ] );
    }

    $ENV{'REMOTE_USER'} = $username;

    # If root is using an API token to call an API as a different user then we mask the
    # API token while loading the ACLs so that it doesn’t try to load the ACL list from
    # the specified user’s API tokens.
    local $ENV{'WHM_API_TOKEN_NAME'};

    Whostmgr::ACLS::clear_acls();
    Whostmgr::ACLS::init_acls();

    return;
}

1;
