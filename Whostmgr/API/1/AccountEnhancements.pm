package Whostmgr::API::1::AccountEnhancements;

# cpanel - Whostmgr/API/1/AccountEnhancements.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Whostmgr::AccountEnhancements ();

=encoding utf-8

=head1 NAME

Whostmgr::API::1::AccountEnhancements.pm

=head1 DESCRIPTION

WHM API functions for managing cPanel user account enhancements

=head1 FUNCTIONS

=cut

use Cpanel::AcctUtils::AccountingLog ();
use Whostmgr::API::1::Utils          ();

use constant NEEDS_ROLE => {
    create_account_enhancement   => undef,
    list_account_enhancements    => undef,
    modify_account_enhancement   => undef,
    delete_account_enhancement   => undef,
    assign_account_enhancement   => undef,
    unassign_account_enhancement => undef,
    list_enhancement_limits      => undef,
    set_enhancement_limit        => undef,
};

=head2 create_account_enhancement($args, $metadata)

This function creates a new account enhancement.

=head3 ARGUMENTS

=over

=item name - string - required

The name you want to give to the newly created account enhancement.

=item id - string - required

The identifier of the item you are targeting.

=back

=head3 RETURNS

The data field contains:

=over

=item name - string

The name given of the newly created account enhancement.

=back

=head3 EXAMPLES

=head4 Command line usage

    whmapi1 --output=jsonpretty create_account_enhancement id=sample-enhancement-id name="Sample Enhancement"

The returned data will contain a structure similar to the JSON below:

    {
       "metadata" : {
          "result" : 1,
          "reason" : "OK",
          "version" : 1,
          "command" : "create_account_enhancement"
       },
       "data" : {
          "name" : "Sample Enhancement"
       }
    }

=cut

sub create_account_enhancement ( $args, $metadata, @ ) {

    my $enhancement_name = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );
    my $id               = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'id' );

    my $enhancement = Whostmgr::AccountEnhancements::add( $enhancement_name, $id );
    $metadata->set_ok();
    return { 'name' => $enhancement->get_name() };
}

=head2 list_account_enhancements($args, $metadata)

This function returns a list containing all of the account enhancements on the system.

=head3 ARGUMENTS

No arguments for the API.

=head3 RETURNS

The enhancements field contains:

=over

=item id - string

The enhancement id.

=item name - string

The name of the enhancement.

=back

=head3 EXAMPLES

=head4 Command line usage

    whmapi1 --output=jsonpretty list_account_enhancements

The returned data will contain a structure similar to the JSON below:

    {
       "data" : {
          "enhancements" : [
             {
                "name" : "foo",
                "id" : "bar"
             },
             {
                "name" : "Deluxe Extreme Release Kernel Solutions",
                "id" : "derks",
             }
          ]
       },
       "metadata" : {
          "result" : 1,
          "reason" : "OK",
          "command" : "list_account_enhancements",
          "version" : 1
       }
    }

=cut

sub list_account_enhancements ( $args, $metadata, @ ) {

    $metadata->set_ok();
    my ( $account_enhancements, $warnings ) = Whostmgr::AccountEnhancements::list();
    $metadata->{'output'}->{'warnings'} = $warnings if @$warnings;

    # allows sorting to work without modifications
    my @enhancements = map { $_->TO_JSON() } @$account_enhancements;
    return { 'enhancements' => \@enhancements };
}

=head2 modify_account_enhancement($args, $metadata)

This function updates an existing account enhancement.

=head3 ARGUMENTS

=over 1

=item name - string - required

The name of the enhancement.

=item id - string - optional

The new id for the enhancement.

=back

=head3 RETURNS

The updated enhancement.
The enhancement field contains:

=over

=item id - string

The enhancement id.

=item name - string

The name of the enhancement.

=back

=head3 EXAMPLES

=head4 Command line usage

    whmapi1 modify_account_enhancement name=enhancement-name id=new-enhancement-id --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    {
       "metadata" : {
          "reason" : "OK",
          "version" : 1,
          "result" : 1,
          "command" : "modify_account_enhancement"
       },
       "data" : {
          "enhancement" : {
             "id" : "sample-enhancement-id",
             "name" : "Sample Enhancement"
          }
       }
    }


=cut

sub modify_account_enhancement ( $args, $metadata, @ ) {

    my $name    = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );
    my %updates = (
        'id' => $args->{'id'},
    );
    $metadata->set_ok();
    return { 'enhancement' => Whostmgr::AccountEnhancements::update( $name, %updates ) };
}

=head2 delete_account_enhancement($args, $metadata)

This function removes an account enhancement.

=head3 ARGUMENTS

=over 1

=item name - string - required

The name of the enhancement.

=back

=head3 RETURNS

Only metadata is returned.

=head3 EXAMPLES

=head4 Command line usage

    whmapi1 delete_account_enhancement name="enhancement name" --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    {
       "metadata" : {
          "reason" : "OK",
          "version" : 1,
          "result" : 1,
          "command" : "delete_account_enhancement"
       }
    }


=cut

sub delete_account_enhancement ( $args, $metadata, @ ) {

    my $name = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );
    Whostmgr::AccountEnhancements::delete($name);
    $metadata->set_ok();
    return;
}

=head2 assign_account_enhancement($args, $metadata, undef)

This function assigns an account enhancement to an account.

=head3 ARGUMENTS

=over 1

=item name - string - required

The name of the enhancement.

=item account - string - required

The username of the account.

=back

=head3 RETURNS

Only metadata is returned.

=head3 EXAMPLES

=head4 Command line usage

    whmapi1 assign_account_enhancement name="enhancement name" user=divoc --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    {
       "metadata" : {
          "reason" : "OK",
          "version" : 1,
          "result" : 1,
          "command" : "assign_account_enhancement"
       }
    }

=cut

sub assign_account_enhancement ( $args, $metadata, @ ) {

    my $name    = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );
    my $account = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'account' );
    Whostmgr::AccountEnhancements::assign( $name, $account );
    $metadata->set_ok();
    Cpanel::AcctUtils::AccountingLog::append_entry( "ASSIGN_ACCOUNT_ENHANCEMENT", [ $name, $account ] );
    return;
}

=head2 unassign_account_enhancement($args, $metadata, undef)

This function removes an account enhancement from an account.

=head3 ARGUMENTS

=over 1

=item name - string - required

The name of the enhancement.

=item account - string - required

The username of the account.

=back

=head3 RETURNS

Only metadata is returned.

=head3 EXAMPLES

=head4 Command line usage

    whmapi1 unassign_account_enhancement name="enhancement name" user=divoc --output=jsonpretty

The returned data will contain a structure similar to the JSON below:

    {
       "metadata" : {
          "reason" : "OK",
          "version" : 1,
          "result" : 1,
          "command" : "assign_account_enhancement"
       }
    }

=cut

sub unassign_account_enhancement ( $args, $metadata, @ ) {

    my $name    = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );
    my $account = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'account' );
    Whostmgr::AccountEnhancements::unassign( $name, $account );
    $metadata->set_ok();
    Cpanel::AcctUtils::AccountingLog::append_entry( "UNASSIGN_ACCOUNT_ENHANCEMENT", [ $name, $account ] );
    return;
}

=head2 list_enhancement_limits($args, $metadata, undef)

This function lists AccountEnhancement limits.

=head3 ARGUMENTS

=over 1

=item account - string - required

The username of the reseller account.

=back

=head3 RETURNS

The enhancements field contains:

=over

=item id - string

The enhancement id.

=item name - string

The name of the enhancement.

=back

=head3 EXAMPLES

=head4 Command line usage

    whmapi1 --output=jsonpretty list_enhancement_limits account="reseller"

The returned data will contain a structure similar to the JSON below:

    {
       "data" : {
           limits: {
                sample-enhancement-id: {
                    "limit"  : "15",
                    "limited": "1",
                    "usage": "5"
                },
                derks: {
                    "limit"  : "0",
                    "limited": "0",
                    "usage": "30"
                }
           }
       },
       "metadata" : {
          "result" : 1,
          "reason" : "OK",
          "command" : "list_enhancement_limits",
          "version" : 1
       }
    }

=cut

sub list_enhancement_limits ( $args, $metadata, @ ) {
    my $account = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'account' );

    require Whostmgr::AccountEnhancements::Reseller;
    my ( $limits, $warnings ) = Whostmgr::AccountEnhancements::Reseller::list_enhancement_limits($account);
    $metadata->{'output'}->{'warnings'} = $warnings if @$warnings;

    $metadata->set_ok();
    return { 'limits' => $limits };
}

=head2 set_enhancement_limit($args, $metadata, undef)

This function sets AccountEnhancement limits.

=head3 ARGUMENTS

=over 1

=item account - string - required

The username of the reseller account.

=item id - string

The AccountEnhancement id you want to apply the assignment limit.

=item limited - boolean

If there is an assignment limit or if it is unlimited.

=item limit - number

The assignment limit amount.

=back

=head3 RETURNS

Only metadata is returned.

=head3 EXAMPLES

=head4 Command line usage

    whmapi1 set_enhancement_limit account="reseller" id="quacken-deluxe-install" limited="1" limit="12"

The returned data will contain a structure similar to the JSON below:

    {
       "metadata" : {
          "reason" : "OK",
          "version" : 1,
          "result" : 1,
          "command" : "set_enhancement_limit"
       }
    }

=cut

sub set_enhancement_limit ( $args, $metadata, @ ) {
    my $account = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'account' );
    my $id      = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'id' );
    my $limited = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'limited' );

    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die( $limited, 'limited' );

    my $limit = $limited ? Whostmgr::API::1::Utils::get_length_required_argument( $args, 'limit' ) : $args->{'limit'};

    require Whostmgr::AccountEnhancements::Reseller;
    Whostmgr::AccountEnhancements::Reseller::set_enhancement_limit( $account, $id, $limited, $limit );

    $metadata->set_ok();
    return;
}

1;
