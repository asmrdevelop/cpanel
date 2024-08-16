# cpanel - Whostmgr/AccountEnhancements/AccountEnhancement.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::AccountEnhancements::AccountEnhancement;

use cPstrict;
use Carp ();
use Cpanel::Imports;
use Whostmgr::AccountEnhancements::Validate ();

=encoding utf-8

=head1 NAME

Whostmgr::AccountEnhancements::AccountEnhancement.pm

=head1 DESCRIPTION

WHM functions for modifying cPanel account enhancement data.

=head1 FUNCTIONS

=head2 new( $class, %args )

Create a new AccountEnhancement object

=head3 ARGUMENTS

=over

=item class - string

Optional. Constructors pass the package name as a parameter.

=item args - hash

A hash consisting of the necessary fields for an AccountEnhancement object or C<thaw>.

When creating a new enhancement, the following arguments are expected:

=over 1

=item id - string

Required. The identifier of the Account Enhancement.

=item name - string

Required. The name of the enhancement.

=back

When you want to turn an enhancement hashref back into an object, you can use the C< thaw > argument.

=over 1

=item thaw - hashref

It is expected the values will validated using C<AccountEnhancements::Validate>

=back

=back

=head3 RETURNS

Returns a new AccountEnhancement object.

=cut

sub new ( $class, %args ) {

    if ( $args{'thaw'} ) {

        Carp::croak("The “thaw” argument must be a hash reference.") if ref $args{'thaw'} ne 'HASH';

        my $self = bless {
            'id'   => undef,
            'name' => undef,
        }, $class;

        $self->set_id( $args{'thaw'}->{'id'} );
        $self->set_name( $args{'thaw'}->{'name'} );

        return $self;

    }

    my $self = bless {
        'id'   => undef,
        'name' => undef,
    }, $class;

    $self->set_id( $args{'id'} );
    $self->set_name( $args{'name'} );

    return $self;
}

=head2 set_id( $self, $id )

Sets the identifier of an AccountEnhancement object.

=head3 ARGUMENTS

=over

=item self - AccountEnhancement object

Required. The AccountEnhancement object you want to modify.

=item id - string

Required. The new identifier of the AccountEnhancement object.

=back

=head3 RETURNS

Returns the AccountEnhancement object.

=cut

sub set_id ( $self, $id ) {
    $self->{'id'} = $id;
    return $self;
}

=head2 set_name( $self, $name )

Sets the name of an AccountEnhancement object.

=head3 ARGUMENTS

=over

=item self - AccountEnhancement object

Required. The AccountEnhancement object you want to modify.

=item name - string

Required. The new name of the AccountEnhancement object.

=back

=head3 RETURNS

Returns the AccountEnhancement object.

=cut

sub set_name ( $self, $name ) {
    $self->{'name'} = $name;
    return $self;
}

=head2 get_id( $self )

Gets the identifier of an AccountEnhancement object.

=head3 ARGUMENTS

=over

=item self - AccountEnhancement object

Required. The AccountEnhancement object you want to retrieve information from.

=back

=head3 RETURNS

Returns the identifier of the AccountEnhancement object.

=cut

sub get_id ($self) {
    return $self->{'id'};
}

=head2 get_name( $self )

Gets the name of an AccountEnhancement object.

=head3 ARGUMENTS

=over

=item self - AccountEnhancement object

Required. The AccountEnhancement object you want to retrieve information from.

=back

=head3 RETURNS

Returns the name of the AccountEnhancement object.

=cut

sub get_name ($self) {
    return $self->{'name'};
}

=head2 add_account( $self, $account )

Grant a cPanel account access to an AccountEnhancement.

=head3 ARGUMENTS

=over

=item self - AccountEnhancement object

Required. The AccountEnhancement object you want to modify.

=item account - string

Required. The username of the account to allow access.

=back

=head3 RETURNS

Returns 1 when saving is successful.

=head3 THROWS

=over 1

=item When the account doesn't exist

=item When the account is not owned by the current user

=item When Cpanel::Config::CpUserGuard fails

=item When the user is already assigned the enhancement

=back

=cut

sub add_account ( $self, $account ) {

    require Cpanel::Config::CpUserGuard;
    require Whostmgr::ACLS;
    require Whostmgr::Authz;
    require Whostmgr::AccountEnhancements::Reseller;
    require Cpanel::AcctUtils::Account;
    require Cpanel::Exception;

    Cpanel::AcctUtils::Account::accountexists_or_die($account);
    Whostmgr::ACLS::init_acls();
    Whostmgr::AccountEnhancements::Validate::validate_access();
    Whostmgr::Authz::verify_account_access($account);

    my $userdata = Cpanel::Config::CpUserGuard->new($account);
    die Cpanel::Exception->create_raw( locale()->maketext( "The system could not load the [asis,userdata] file for the “[_1]” user.", $account ) ) if !$userdata;

    my $key = $self->account_key();
    if ( $userdata->{'data'}{$key} ) {
        die Cpanel::Exception::create( 'AccountAccessAlreadyExists', "The “[_2]” account already has access to the “[_1]” enhancement.", [ $self->get_name, $account ] );
    }

    Whostmgr::AccountEnhancements::Reseller::update_usage( $userdata->{'data'}{'OWNER'}, $self->get_id(), 1 );
    $userdata->{'data'}{$key} = $self->get_id();
    if ( !$userdata->save() ) {
        Whostmgr::AccountEnhancements::Reseller::update_usage( $userdata->{'data'}{'OWNER'}, $self->get_id(), -1 );
        die Cpanel::Exception->create_raw( locale()->maketext( "The system could not assign the “[_1]” enhancement to the “[_2]” account.", $self->get_name, $account ) );
    }

    return 1;
}

=head2 remove_account( $self, $account )

Revoke a cPanel account access to an AccountEnhancement.

=head3 ARGUMENTS

=over

=item self - AccountEnhancement object

Required. The AccountEnhancement object you want to retrieve information from.

=item account - string

Required. The username of the account.

=back

=head3 RETURNS

Returns 1 when saving is successful.

=head3 THROWS

=over 1

=item When the account doesn't exist

=item When the account is not owned by the current user

=item When Cpanel::Config::CpUserGuard fails

=item When the user is not assigned the enhancement

=back

=cut

sub remove_account ( $self, $account ) {

    require Cpanel::Config::CpUserGuard;
    require Whostmgr::ACLS;
    require Whostmgr::Authz;
    require Whostmgr::AccountEnhancements::Reseller;
    require Cpanel::AcctUtils::Account;
    require Cpanel::Exception;

    Cpanel::AcctUtils::Account::accountexists_or_die($account);
    Whostmgr::ACLS::init_acls();
    Whostmgr::AccountEnhancements::Validate::validate_access();
    Whostmgr::Authz::verify_account_access($account);

    my $userdata = Cpanel::Config::CpUserGuard->new($account);
    die Cpanel::Exception->create_raw( locale()->maketext( "The system could not load the [asis,userdata] file for the “[_1]” user.", $account ) ) if !$userdata;

    my $key = $self->account_key();
    if ( !exists( $userdata->{'data'}{$key} ) || $userdata->{'data'}{$key} ne $self->get_id() ) {
        die Cpanel::Exception->create_raw( locale()->maketext( "The “[_2]” account does not have access to the “[_1]” enhancement.", $self->get_name, $account ) );
    }

    Whostmgr::AccountEnhancements::Reseller::update_usage( $userdata->{'data'}{'OWNER'}, $self->get_id(), -1 );
    delete $userdata->{'data'}{$key} if exists( $userdata->{'data'}{$key} );
    if ( !$userdata->save() ) {
        Whostmgr::AccountEnhancements::Reseller::update_usage( $userdata->{'data'}{'OWNER'}, $self->get_id(), 1 );
        die Cpanel::Exception->create_raw( locale()->maketext( "The system could not unassign the “[_1]” enhancement from the “[_2]” account.", $self->get_name, $account ) );
    }

    return 1;
}

=head2 account_key()

Return the cpUser key for assigning an Account Enhancement. This key is used to allow a cPanel account access to the Account Enhancement.

=head3 ARGUMENTS

=over

=item self - AccountEnhancement object

Required. The automatic reference to this object.

=back

=head3 RETURNS

Returns a string which is the key to use for this enhancement.


=cut

sub account_key ($self) {

    return 'ACCOUNT-ENHANCEMENT-' . $self->get_name();
}

=head2 TO_JSON( $self )

Convert the AccountEnhancement object to JSON format.

=head3 ARGUMENTS

=over

=item self - AccountEnhancement object

Required. The AccountEnhancement object you want to retrieve information from.

=back

=head3 RETURNS

Returns the ID, name, and accounts of the AccountEnhancement object in JSON format.

=cut

sub TO_JSON ($self) {
    return {
        'id'   => $self->get_id(),
        'name' => $self->get_name(),
    };
}

1;
