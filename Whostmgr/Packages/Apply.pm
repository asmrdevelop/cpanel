package Whostmgr::Packages::Apply;

# cpanel - Whostmgr/Packages/Apply.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Packages::Apply - Logic for handling updating accounts when a package changes.

=head1 SYNOPSIS

    use Whostmgr::Packages::Apply;

    my ($successes_ar, $failures_ar) = Whostmgr::Packages::Apply::apply_package_to_accounts( $package_name, $accounts_owner );

=head1 DESCRIPTION

    This module contains functionality to apply package settings to accounts using
    the package.

=head2 apply_package_to_accounts( $package_name, $accounts_owner, $logger );

Apply the settings from the given package to accounts using that package. If the specified owner
does not have root-level privileges, only accounts owned by that owner will be updated.

=over

=item Input

=over

=item C<SCALAR> - $package_name

The name of the package whose settings will be applied to the accounts.

=item C<SCALAR> - $accounts_owner

The username of the owner whose accounts will have the package settings applied.

If the given user possesses root-level privileges, all accounts using the specified
package will be updated.

=back

=item Output

=over

=item C<ARRAYREF> - $successes_ar

An C<ARRAYREF> containing the usernames of the accounts where the package settings were
successfully applied.

=item C<ARRAYREF> - $failures_ar

An C<ARRAYREF> where each element is a C<HASHREF> containing C<user> and C<error> keys
for any accounts where applying the package settings failed.

=back

=back

=cut

sub apply_package_to_accounts ( $package, $owner ) {

    # Owner is required so we know who to initialize ACLs as
    if ( !length $package || !length $owner ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create_raw("You must specify the package name and accounts’ owner.");
    }

    local $ENV{'REMOTE_USER'} = $owner;

    # upacct requires ACLs to be initialized for a hasroot check
    require Whostmgr::ACLS;
    local %Whostmgr::ACLS::ACL;
    Whostmgr::ACLS::init_acls();

    # We pass an empty string as the owner if the user hasroot to preserve
    # historical behavior where Whostmgr::Packages::Mod applied the package
    # changes to every account using the package when the user had root-level
    # privileges.
    require Whostmgr::AcctInfo;
    my %ACCTS = Whostmgr::AcctInfo::acctlister( $package, Whostmgr::ACLS::hasroot() ? "" : $owner );

    my ( $fail, $success ) = ( [], [] );

    require Whostmgr::Accounts::Upgrade;
    foreach my $acct ( sort keys %ACCTS ) {

        local $@;
        my ( $status, $statusmsg, $rawout ) = eval { Whostmgr::Accounts::Upgrade::upacct( 'user' => $acct, 'pkg' => $package, 'skip_updateuserdomains' => 1 ) };

        if ( $@ || !$status ) {
            my $err = $@ || $statusmsg;
            push @$fail, { user => $acct, error => $err };
        }
        else {
            push @$success, $acct;
        }

    }

    if (@$success) {
        require Cpanel::Userdomains;
        Cpanel::Userdomains::updateuserdomains();
        require Cpanel::Config::userdata::UpdateCache;
        Cpanel::Config::userdata::UpdateCache::update(@$success);
    }

    Whostmgr::Accounts::Upgrade::restart_services_after_account_upgrade();

    return ( $success, $fail );
}

1;
