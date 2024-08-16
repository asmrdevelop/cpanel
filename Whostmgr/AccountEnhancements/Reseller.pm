package Whostmgr::AccountEnhancements::Reseller;

# cpanel - Whostmgr/AccountEnhancements/Reseller.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Exception;
use Cpanel::Imports;
use Whostmgr::AccountEnhancements           ();
use Whostmgr::AccountEnhancements::Validate ();
use Whostmgr::Limits::Resellers             ();

=encoding utf-8

=head1 NAME

Whostmgr::AccountEnhancements::Reseller.pm

=head1 DESCRIPTION

This module provides functionality to support managing Account Enhancement assignment
limits for resellers.

=cut

use constant DEFAULT_RESELLER_LIMIT => { 'limited' => 1, 'limit' => 0, 'usage' => 0 };

=head1 FUNCTIONS

=cut

=head2 set_enhancement_limit( $username, $enhancement_id, $limited, $limit )

Set an AccountEnhancement assignment limit for a reseller.

=head3 ARGUMENTS

=over

=item username - string

Required. The username of the reseller account to limit AccountEnhancement assignments.

=item enhancement_id - string

Required. The AccountEnhancement id you want to apply the assignment limit.

=item limited - boolean

Required. If there is an assignment limit or if it is unlimited.

=item limit - number

Required. The assignment limit amount.

=back

=head3 RETURNS

Returns 1 when the limit set is successful.

=head3 THROWS

=over 1

=item When the user does not have root privileges

=item When username is not a reseller account username.

=item When the limit is not an integer.

=item When the limited is not an 0 or 1.

=item When the enhancement_id is invalid.

=back

=cut

sub set_enhancement_limit ( $username, $enhancement_id, $limited, $limit ) {

    Whostmgr::AccountEnhancements::Validate::validate_admin_only();
    Whostmgr::AccountEnhancements::Validate::validate_reseller($username);
    Whostmgr::AccountEnhancements::Validate::validate_id($enhancement_id);

    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die( $limited, 'limited' );

    Whostmgr::AccountEnhancements::Validate::validate_reseller_limit($limit) if defined($limit);

    my $all_limits = Whostmgr::Limits::Resellers::load_all_reseller_limits(1);

    my %setting = %{ DEFAULT_RESELLER_LIMIT() };
    if ( ref $all_limits->{'data'}{$username}{'limits'}{'account_enhancements'}{$enhancement_id} eq 'HASH' ) {
        %setting = %{ $all_limits->{'data'}{$username}{'limits'}{'account_enhancements'}{$enhancement_id} };
    }

    $setting{'limited'} = $limited;
    $setting{'limit'}   = int $limit if defined($limit);

    $all_limits->{'data'}{$username}{'limits'}{'account_enhancements'}{$enhancement_id} = \%setting;

    if ( !Whostmgr::Limits::Resellers::saveresellerlimits($all_limits) ) {
        die Cpanel::Exception->create("The system failed to save the reseller limits.");
    }

    return 1;
}

=head2 list_enhancement_limits( $username )

Lists AccountEnhancement limits.

=head3 ARGUMENTS

=over

=item username - string

Required. The username of the reseller account to list the AccountEnhancement limits.

=back

=head3 RETURNS

Returns a hash containing the AccountEnhancement list of limits for the specified reseller.

=head3 THROWS

=over 1

=item When the user does not have root privileges

=item When username is not a reseller account username.

=back

=cut

sub list_enhancement_limits ($username) {

    require Cpanel::Context;
    Cpanel::Context::must_be_list();

    Whostmgr::AccountEnhancements::Validate::validate_reseller($username);
    Whostmgr::AccountEnhancements::Validate::validate_owns_account($username);

    my $limits = Whostmgr::Limits::Resellers::load_resellers_limits($username);
    my ( $enhancements, $warnings ) = Whostmgr::AccountEnhancements::list_unique_ids();

    my %current_limits;
    foreach my $enhancement ( @{$enhancements} ) {
        my $id = $enhancement->get_id();
        $current_limits{$id} = $limits->{'limits'}{'account_enhancements'}{$id} // DEFAULT_RESELLER_LIMIT;
    }
    return ( \%current_limits, $warnings );

}

=head2 update_usage ( $reseller_account, $enhancement_id, $modifier )

Updates the count of Account Enhancements assigned to users owned by a reseller.

=head3 ARGUMENTS

=over

=item reseller_account - string

Required. The username of the reseller account to update the AccountEnhancement limits for.

=item enhancement_id - string

Required. The ID of the Account Enhancement that is being assigned to a user owned by the reseller.

=item modifier - integer

Required. The number to increment the current assignment count by, in intervals of either 1 or -1.

=back

=head3 RETURNS

Returns 1 on success. 0 if the provided $reseller_account is not a valid reseller, dies otherwise.

=head3 THROWS

=over 1

=item When the modifier increment count is greater than 1 or less than -1

=item When the enhancement ID is invalid

=item When the reseller is at their assignment limit for the provided enhancement ID

=item When the attempt to update the reseller limits fails

=back

=cut

sub update_usage ( $reseller_account, $enhancement_id, $modifier ) {

    # Avoid adding a root entry in reseller-limits.yaml file.
    return 0 if $reseller_account eq 'root';

    $modifier = int $modifier;
    if ( $modifier != -1 && $modifier != 1 ) {
        die Cpanel::Exception->create("Reseller [asis,Account Enhancement] usage can only be modified in increments of 1.");
    }

    my $has_root        = eval { Whostmgr::AccountEnhancements::Validate::validate_admin_only() };
    my $reseller_status = eval { Whostmgr::AccountEnhancements::Validate::validate_reseller($reseller_account) };
    return 0 if ( !$reseller_status && !$has_root );

    Whostmgr::AccountEnhancements::Validate::validate_id_format($enhancement_id);

    my $limits   = Whostmgr::Limits::Resellers::load_all_reseller_limits(1);
    my $settings = $limits->{'data'}{$reseller_account}{'limits'}{'account_enhancements'}{$enhancement_id} // { %{ DEFAULT_RESELLER_LIMIT() } };

    $settings->{'usage'} += $modifier;
    $settings->{'usage'} = 0 if ( $settings->{'usage'} < 0 );

    # Assignment will be rejected if:
    # * The user making the adjustment is a non-root reseller and..
    # * The user is limited, attempting to increase their usage count by 1, and over their usage limit in the process of doing so.
    if ( !$has_root && $settings->{'limited'} && $modifier == 1 && $settings->{'usage'} > $settings->{'limit'} ) {

        # Need to close open lock since saveresellerlimits won't be called to close it.
        require Cpanel::SafeFile;
        Cpanel::SafeFile::safeclose( $limits->{'fh'}, $limits->{'safefile_lock'} );

        die Cpanel::Exception->create( "You have reached the maximum number of “[_1]” assignments for the “[_2]” [asis,Account Enhancement] [asis,ID].", [ $settings->{'limit'}, $enhancement_id ] );
    }

    $limits->{'data'}{$reseller_account}{'limits'}{'account_enhancements'}{$enhancement_id} = $settings;
    if ( !Whostmgr::Limits::Resellers::saveresellerlimits($limits) ) {
        die Cpanel::Exception->create("The system failed to save the reseller limits.");
    }

    return 1;
}

=head2 recalculate_usage($reseller)

if $reseller is a reseller account, recalculate Account Enhancement
usage and update the reseller's usage to the new values.

=head3 ARGUMENTS

=over 1

=item $reseller

The username of the reseller account

=back

=head3 RETURNS

Returns a hash reference of the recalculated usages.

    $usage = {
        some_enhancement_id => 100
        another_id = 200
    }

=head3 EXCEPTIONS

=over

=item When the username provided is not a reseller.

=item When the system fails to save the reseller limits

=item When supporting methods from C<Whostmgr::Accounts::List::listaccts> or C<Whostmgr::AccountEnhancements::findByAccount> fail.

=back

=cut

sub recalculate_usage ($reseller) {

    $reseller //= '';

    require Cpanel::AcctUtils::Account;
    Cpanel::AcctUtils::Account::accountexists_or_die($reseller);
    Whostmgr::AccountEnhancements::Validate::validate_reseller($reseller);

    require Whostmgr::Accounts::List;
    my %query = ( search => $reseller, searchmethod => 'exact', searchtype => 'owner' );
    my ( $count, $accounts ) = Whostmgr::Accounts::List::listaccts(%query);
    my %usage;

    foreach my $account ( @{$accounts} ) {
        my ( $enhancements, $warnings ) = Whostmgr::AccountEnhancements::findByAccount( $account->{'user'} );
        foreach my $enhancement ( @{$enhancements} ) {
            $usage{ $enhancement->get_id() } += 1;
        }
    }

    my $limits = Whostmgr::Limits::Resellers::load_all_reseller_limits(1);
    foreach my $enhancement_id ( keys %usage ) {
        my $settings = $limits->{'data'}{$reseller}{'limits'}{'account_enhancements'}{$enhancement_id} // { %{ DEFAULT_RESELLER_LIMIT() } };
        $settings->{'usage'} = $usage{$enhancement_id};
        $limits->{'data'}{$reseller}{'limits'}{'account_enhancements'}{$enhancement_id} = $settings;
    }

    if ( !Whostmgr::Limits::Resellers::saveresellerlimits($limits) ) {
        die Cpanel::Exception->create("The system failed to save the reseller limits.");
    }

    return \%usage;

}

=head2 update_owner ( $old_owner, $new_owner, $account )

Transfers the Account Enhancement assignment counts of a reseller-owned user to a new owner.

=head3 ARGUMENTS

=over

=item old_owner - string

Required. The username of the current reseller account that owns the user with assigned Account Enhancement(s).

=item new_owner - string

Required. The username of the new reseller account that owns the user with assigned Account Enhancement(s).

=item account - string

Required. The account with assigned Account Enhancement(s) that is having ownership transferred.

=back

=head3 RETURNS

Returns 1 on success, dies otherwise.

=head3 THROWS

=over 1

=item When the system encounters an error attempting to find Account Enhancements assigned to $account

=item When the system fails to update the usage count on either the old or new owner account

=back

=cut

sub update_owner ( $old_owner, $new_owner, $account ) {

    my ( $enhancements, $warnings ) = Whostmgr::AccountEnhancements::findByAccount($account);
    foreach my $enhancement ( @{$enhancements} ) {
        update_usage( $old_owner, $enhancement->get_id(), -1 );
        update_usage( $new_owner, $enhancement->get_id(), 1 );
    }

    return 1;
}

1;
