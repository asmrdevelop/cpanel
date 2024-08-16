package Whostmgr::Accounts::MassModify;

# cpanel - Whostmgr/Accounts/MassModify.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Accounts::MassModify

=head1 DESCRIPTION

Encapsulates the logic needed for the “Modify/Upgrade Multiple Accounts” UI.

This module is just a thin wrapper around C<Cpanel::LinkedNode::Worker::WHM::Accounts::change_account_package>
and C<Whostmgr::Accounts::Modify::mass_modify>.

For anything new, consider using those modules directly.

=head1 FUNCTIONS

=cut

use Cpanel::AcctUtils::Load ();

use Whostmgr::ACLS  ();
use Whostmgr::Authz ();

my @root_only = (
    'owner',
    'theme',
    'startdate',
);

my %cpuser_field = (
    owner     => 'OWNER',
    theme     => 'RS',
    startdate => 'STARTDATE',
    locale    => 'LOCALE',
);

=head2 do ( $usernames_ar, $new_values_hr, $output_obj )

Performs a mass-modification of the specified accounts.

This function only dies if a non-root user attempts to pass in new values they’re
not permitted to change.

Otherwise, success or failure is reported for each account via a C<Cpanel::Output> object.

=over

=item INPUT

=over

=item $usernames_ar

An ARRAYREF of the usernames for the accounts to modify.

=item $new_values_hr

A HASHREF of new values to apply to the accounts being modified.

Supported keys are:

=over

=item package

A new plan/package to apply to the accounts.

=item owner

The username of an account to set as the owner of the accounts.

=item startdate

A timestamp in epoch format to set as the start date of the accounts.

=item locale

A new locale to apply to  the accounts.

=back

=item $output_obj

A C<Cpanel::Output> object to write the output of the accounts.

=back

=item OUTPUT

This function has no outputs. Results are reported via the C<Cpanel::Output> object
passed in.

=back

=cut

sub do ( $usernames_ar, $new_values_hr, $output_obj ) {    ## no critic qw(Subroutines::ProhibitManyArgs) adding prohibit due to bug with signatures

    if ( !Whostmgr::ACLS::hasroot() ) {
        my @forbidden = grep { exists $new_values_hr->{$_} } @root_only;

        if (@forbidden) {
            die "Forbidden: @forbidden\n";
        }
    }

    if ( !@$usernames_ar ) {
        $output_obj->out("You have not selected any users - no modifications performed");
        return;
    }

    Cpanel::AcctUtils::Load::loadaccountcache();

    my $allowed_users = [];
    foreach my $username (@$usernames_ar) {
        if ( !eval { Whostmgr::Authz::verify_account_access($username); 1 } ) {
            $output_obj->out("You do not have permission to modify the user $username.");
            next;
        }
        push @$allowed_users, $username;
    }

    return if !@$allowed_users;

    my $pkg = delete $new_values_hr->{package};
    _apply_package_change_to_users( $allowed_users, $pkg, $output_obj ) if length $pkg;

    _apply_account_modifications( $allowed_users, $new_values_hr, $output_obj ) if keys %$new_values_hr;

    $output_obj->out("All Modifications Complete");

    return;
}

sub _apply_package_change_to_users ( $users_ar, $pkg, $output_obj ) {

    $output_obj->out("Applying package change to users …");

    require Whostmgr::Packages::Fetch;

    foreach my $user (@$users_ar) {

        $output_obj->out("Applying package change to $user … ");

        # This has to be fetched for each user since we need to rebuild the package list
        # if we’re changing bandwidth limits or quotas via a package change.
        my $pkglist_ref = Whostmgr::Packages::Fetch::fetch_package_list( 'want' => 'creatable', 'skip_number_of_accounts_limit' => 1, 'package' => $pkg );
        my %CREATEABLE  = map { $_ => 1 } keys %$pkglist_ref;

        if ( $CREATEABLE{$pkg} ) {
            require Cpanel::LinkedNode::Worker::WHM::Accounts;

            # We can't avoid the upateuserdomains here
            # since we need it to rebuild so Whostmgr::Packages::Fetch::fetch_package_list
            # will be updated with the available packages since we could be changing a bandwidth limit
            local $@;
            my ( $status, $reason ) = eval { Cpanel::LinkedNode::Worker::WHM::Accounts::change_account_package( $user, $pkg ) };

            if ( $@ || !$status ) {
                require Cpanel::Exception;
                my $error = $@ ? $@ : $reason;
                $output_obj->out( Cpanel::Exception::get_string($error) );
            }
            else {
                $output_obj->out($reason);
            }

        }

    }

    return;
}

sub _apply_account_modifications ( $users_ar, $new_values_hr, $output_obj ) {    ## no critic qw(Subroutines::ProhibitManyArgs) adding prohibit due to bug with signatures

    my %modify_opts;
    $modify_opts{ $cpuser_field{$_} } = $new_values_hr->{$_} for keys %$new_values_hr;

    $output_obj->out("Applying additional options to users …");

    require Whostmgr::Accounts::Modify;
    my $result_hr = Whostmgr::Accounts::Modify::mass_modify( $users_ar, %modify_opts );

    foreach my $user ( sort keys %{ $result_hr->{users} } ) {

        my $had_error;
        foreach my $modification ( @{ $result_hr->{users}{$user} } ) {
            if ( !$modification->{result} ) {

                my $reason = $modification->{reason};

                if ( $modification->{proxied_from} ) {
                    my $hostname = $modification->{proxied_from}[-1];
                    $output_obj->out("Failed to modify “$user” on “$hostname”: $reason");
                }
                else {
                    $output_obj->out("Failed to modify “$user”: $reason");
                }

                $had_error = 1;
            }
        }

        if ( !$had_error ) {
            $output_obj->out("Successfully modified “$user”");
        }

    }

    return;
}
