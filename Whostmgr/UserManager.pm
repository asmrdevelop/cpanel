
# cpanel - Whostmgr/UserManager.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::UserManager;

use strict;
use warnings;

use Cpanel::ApiUtils::Execute ();
use Cpanel::LoadModule        ();

=head1 NAME

Whostmgr::UserManager

=head1 DESCRIPTION

This is the interface into User Manager code for applications/scripts running as root.

=head1 FUNCTIONS

=head2 domains_with_data(CPUSER)

Given a cPanel user CPUSER, returns an array ref containing any domains for which
user data already exists. This may include some domains which are not even owned
by the account, but for which service accounts exist.

=cut

sub domains_with_data {
    my ($cpuser) = @_;

    # If these roles are disabled, then none of the subaccount types are available.
    # Skip the privilege de-escalation and just return an empty ref.
    require Cpanel::Server::Type::Profile::Roles;
    if ( !Cpanel::Server::Type::Profile::Roles::are_roles_enabled( { match => "any", roles => [qw(MailReceive FTP WebDisk)] } ) ) {
        return [];
    }

    my $result = Cpanel::ApiUtils::Execute::externally_as_user(
        $cpuser,
        'UserManager',
        'list_users',
        {}
    );
    my $data = $result->{result}{data};
    my %domains;
    for my $rec (@$data) {
        my $domain = $rec->{domain} || next;
        $domains{$domain} = 1;
    }
    return [ sort keys %domains ];
}

=head2 upgrade_if_needed(CPUSER, UPGRADE_OPTS)

Given a cPanel account CPUSER and a hash ref of options for the upgrade
UPGRADE_OPTS, the following operations will be performed:

1. Temporarily disable quota, if any, for CPUSER.

2. Drop privileges to CPUSER.

3. Call Whostmgr::UserManager::Storage::Upgrade::upgrade_if_needed with parameters specified by UPGRADE_OPTS.

4. Restore privileges.

5. Reenable quota, if any, for CPUSER.

=head3 Contents of of UPGRADE_OPTS

note - string - (optional) If set, the note is added to the log statement for the upgrade.

quiet - boolean - (optional) If set, the log output is suppressed except in case of failures.

expire_invites - boolean - (optional) If set, also expire all pending invites sent by the affected
cPanel accounts. This is used during transfers and restores, because the invites are no longer
meaningful on the destination server.

I<See also:> perldoc Cpanel::UserManager::Storage::Upgrade

=head3 Returns

n/a

=head3 Throws

If anything goes wrong with the database upgrade, an exception will be thrown.
The caller needs to be ready to either catch the exception or exit on failure.

=cut

sub upgrade_if_needed {
    my ( $cpuser, $upgrade_opts ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::AccessIds');
    Cpanel::LoadModule::load_perl_module('Cpanel::UserManager::Storage::Upgrade');
    Cpanel::LoadModule::load_perl_module('Cpanel::Quota::Temp');

    my $temp_quota = Cpanel::Quota::Temp->new( user => $cpuser );

    $temp_quota->disable();

    Cpanel::AccessIds::do_as_user_with_exception(
        $cpuser,
        sub {
            Cpanel::UserManager::Storage::Upgrade::upgrade_if_needed(%$upgrade_opts);
        }
    );

    $temp_quota->restore();

    return;
}

1;
