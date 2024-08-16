# cpanel - Whostmgr/AccountEnhancements/Validate.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::AccountEnhancements::Validate;

use cPstrict;
use Cpanel::Imports;
use Cpanel::ArrayFunc                      ();
use Cpanel::Exception                      ();
use Cpanel::StringFunc                     ();
use Cpanel::Validate::PackageName          ();
use Whostmgr::AccountEnhancements          ();
use Whostmgr::AccountEnhancements::Install ();

=encoding utf-8

=head1 NAME

Whostmgr::AccountEnhancements::Validate.pm

=head1 DESCRIPTION

Internal functions for validating account enhancement specific data.

=head1 CONSTANTS

C<MAX_NAME_LENGTH>

The maximum string length of an account enhancement name.

=cut

use constant MAX_NAME_LENGTH => 80;

=head1 FUNCTIONS

=head2 validate_id( $enhancement_id )

Validate that the given enhancement id matches a plugin on the system.

=head3 ARGUMENTS

=over

=item enhancement_id - string

Required. The id for the Account Enhancement you want to validate.

=back

=head3 THROWS

=over

=item Missing enhancement_id

Throws a "MissingParameter" exception if 'enhancement_id' parameter is undefined.

=item Invalid enhancement_id

Throws an "InvalidParameter" exception if 'enhancement_id' parameter does not match an existing plugin id.

=back

=head3 RETURNS

Returns 1 on successful validation. Dies in other cases.

=cut

sub validate_id ($enhancement_id) {

    die Cpanel::Exception::create( "MissingParameter", [ name => 'enhancement_id' ] ) if !defined($enhancement_id);

    my $plugins = Whostmgr::AccountEnhancements::Install::get_installed_plugins();

    die Cpanel::Exception::create( "InvalidParameter", "The “[_1]” enhancement ID is not valid.", [$enhancement_id] )
      if not defined Cpanel::ArrayFunc::first( sub { exists $_->{'id'} && $_->{'id'} eq $enhancement_id }, values %$plugins );

    return 1;

}

=head2 validate_id_format($enhancement_id)

Validate the given enhancement id conforms to the required format.

=head3 ARGUMENTS

=over 1

=item enhancement_id - string

The value to validate.

=back

=head3 RETURNS

Returns 1 if the enhancement id is valid, but dies otherwise.

=head3 THROWS

When the id is not in the expected format.

=cut

sub validate_id_format ($enhancement_id) {

    if ( $enhancement_id !~ /^[0-9a-z_-]{1,32}$/ ) {
        die Cpanel::Exception::create( "InvalidParameter", "The “[_1]” enhancement ID is not valid.", [$enhancement_id] );
    }

    return 1;

}

=head2 validate_name( $name )

Validate that the given name is in the expected format.
See also L<Cpanel::Validate::PackageName> which this uses internally.

=head3 ARGUMENTS

=over

=item name - string

Required. The name for the Account Enhancement you want to validate.

=back

=head3 THROWS

=over

=item Missing name

Throws an "MissingParameter" exception if 'name' parameter is undefined.

=item Invalid name

Throws an "InvalidParameter" exception if 'name' parameter is either too large or too small.

=item Invalid name

Throws an "InvalidCharacters" exception if 'name' parameter does not pass the PackageName validation.

=back

=head3 RETURNS

Returns 1 (int) on successful validation.

=cut

sub validate_name ($name) {

    die Cpanel::Exception::create( "MissingParameter", [ name => 'name' ] ) if !defined($name);

    my $strlen = length($name);
    die Cpanel::Exception::create( "InvalidParameter", "The “[_1]” enhancement name must be between “1” and “[_2]” characters.", [ $name, MAX_NAME_LENGTH ] )
      if $strlen < 1 || $strlen > MAX_NAME_LENGTH;

    eval { Cpanel::Validate::PackageName::validate_or_die($name) };
    if ($@) {
        die Cpanel::Exception::create( "InvalidParameter", "The “[_1]” enhancement name is reserved or contains unsupported characters.", [$name] );
    }

    return 1;
}

=head2 name_exists( $name )

Enhancement names are expected to be unique.
This function determines if a given enhancement name exists on the system.

=head3 ARGUMENTS

=over

=item name - string

Required. The name of the Account Enhancement you want to search for.

=back

=head3 THROWS

=over

=item Missing name

Throws an "MissingParameter" exception if 'name' parameter is undefined.

=item Invalid name

Throws an "InvalidParameter" exception if 'name' parameter already exists in the system.

=back

=head3 RETURNS

Returns 1 if an Account Enhancement with that name does not exist.
Dies if the enhancement exists.

=cut

sub name_exists ($name) {

    die Cpanel::Exception::create( "MissingParameter", [ name => 'name' ] ) if !defined($name);

    #TODO: consider DUCK-5633
    my ( $enhancements, undef ) = Whostmgr::AccountEnhancements::list();
    my ($match) = Cpanel::ArrayFunc::first( sub { defined $_->get_name() && Cpanel::StringFunc::ToUpper( $_->get_name() ) eq Cpanel::StringFunc::ToUpper($name) }, @$enhancements );

    die Cpanel::Exception::create( "InvalidParameter", "The “[_1]” enhancement name already exists on the system.", [$name] )
      if $match;

    return 1;
}

=head2 validate_access( )

Validates that the user has the appropriate ACL's to perform allowed Account Enhancement
operations.

=head3 ARGUMENTS

No arguments

=head3 THROWS

=over

=item When the user running the code does not have the assign-root-account-enhancements ACL.

=back

=head3 RETURNS

Returns 1 when successful.

=cut

sub validate_access () {

    require Whostmgr::ACLS;
    Whostmgr::ACLS::init_acls();
    if ( !Whostmgr::ACLS::checkacl('assign-root-account-enhancements') ) {
        die Cpanel::Exception->create("You do not have access to perform this Account Enhancement operation.");
    }
    return 1;
}

=head2 validate_admin_only( )

Validates that the user is root for admin only operations.

=head3 ARGUMENTS

No arguments

=head3 THROWS

=over

=item When the user running the code does not have root permissions.

=back

=head3 RETURNS

Returns 1 when successful.

=cut

sub validate_admin_only () {

    require Whostmgr::ACLS;
    Whostmgr::ACLS::init_acls();
    die( Cpanel::Exception->create("You must have root privileges to perform this operation.") ) if ( !Whostmgr::ACLS::hasroot() );

    return 1;

}

=head2 validate_reseller($username)

Validates that the user is a reseller.

=head3 ARGUMENTS

=over

=item username - string

Required. The username of the reseller account.

=back

=head3 THROWS

=over

=item Throws a "MissingParameter" exception if 'username' parameter is undefined.

=item When the user is not a reseller.

=back

=head3 RETURNS

Returns 1 when successful.

=cut

sub validate_reseller ($username) {
    die Cpanel::Exception::create( "MissingParameter", [ name => 'username' ] ) if !defined($username);

    require Whostmgr::Resellers::Check;
    if ( !Whostmgr::Resellers::Check::is_reseller($username) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” cPanel account is not a reseller.', [$username] );
    }
    return 1;
}

=head2 validate_reseller_limit($limit)

Validates that the user is a reseller.

=head3 ARGUMENTS

=over

=item limit - integer

Required. The AccountEnhancement limit.

=back

=head3 THROWS

=over

=item When the limit is not an integer.

=back

=head3 RETURNS

Returns 1 when successful.

=cut

sub validate_reseller_limit ($limit) {
    require Cpanel::Validate::Integer;
    Cpanel::Validate::Integer::unsigned( $limit, "limit" );

    return 1;
}

=head2 validate_owns_account($account)

Validates that the account is owned by the caller.

=head3 ARGUMENTS

=over

=item account - string

Required. The username of the account.

=back

=head3 THROWS

=over

=item Throws a "MissingParameter" exception if 'account' parameter is undefined.

=item When the account does not exist.

=item When the account is not owned by the caller.

=back

=head3 RETURNS

Returns 1 when successful.

=cut

sub validate_owns_account ($account) {
    die Cpanel::Exception::create( "MissingParameter", [ name => 'account' ] ) if !defined($account);

    require Whostmgr::ACLS;
    Whostmgr::ACLS::init_acls();

    return 1 if ( defined $ENV{'REMOTE_USER'} && $account eq $ENV{'REMOTE_USER'} ) || Whostmgr::ACLS::hasroot();

    require Cpanel::AcctUtils::Account;
    require Whostmgr::AcctInfo::Owner;
    die Cpanel::Exception::create( 'UserNotFound', [ name => $account ] ) if !Cpanel::AcctUtils::Account::accountexists($account);
    die Cpanel::Exception::create( 'InvalidParameter', "You do not own the “[_1]” cPanel account.", [$account] ) if !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $account );

    return 1;
}

1;

