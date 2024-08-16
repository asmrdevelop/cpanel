# cpanel - Whostmgr/Accounts/Remove/ResellerWithoutDomain.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Accounts::Remove::ResellerWithoutDomain;

use cPstrict;
use AcctLock                         ();
use Cpanel::AcctUtils::AccountingLog ();
use Cpanel::ConfigFiles              ();
use Cpanel::Config::HasCpUserFile    ();
use Cpanel::Config::LoadCpUserFile   ();
use Cpanel::Exception                ();
use Cpanel::Finally                  ();
use Cpanel::Reseller                 ();
use Cpanel::SysAccounts              ();
use Whostmgr::Resellers::Setup       ();

use Carp ();

=head1 NAME

Whostmgr::Accounts::Remove::ResellerWithoutDomain

=head1 DESCRIPTION

Account removal for resellers without domains.

=head1 FUNCTIONS

=head2 is_reseller_without_domain( username => ... )

Given a username, check whether the user is a reseller
without a domain.

Returns: boolean

=cut

sub is_reseller_without_domain (%OPTS) {
    my $username = delete $OPTS{username};
    Carp::croak('need a username') if !$username;

    return 0 if !Cpanel::Reseller::isreseller($username);
    if ( Cpanel::Config::HasCpUserFile::has_readable_cpuser_file($username) ) {
        my $cpuser_hr = Cpanel::Config::LoadCpUserFile::load($username);
        if ( $cpuser_hr->{USER} && !$cpuser_hr->{DOMAIN} ) {
            return 1;
        }
        return 0;
    }
    return 1;
}

=head2 remove( username => ... )

Given a username, remove a reseller without a domain.
If the specified user doesn't exist, is not a reseller,
or has a domain, no action will be taken.

Returns:

  - Status - boolean
  - Reason - string
  - Output - string, for display in UI (currently nothing)

=cut

sub remove (%OPTS) {

    AcctLock::acctlock();
    my $unlock = Cpanel::Finally->new( sub { AcctLock::acctunlock(); } );

    my ( $status, $reason, $output ) = _remove(%OPTS);

    return ( $status, $reason, $output );
}

=head2 _remove()

Private implementation

=cut

sub _remove (%OPTS) {
    my $output = '';

    my $username = $OPTS{username} || $OPTS{user};
    if ( !length $username ) {
        return ( 0, 'No user name supplied: "username" is a required argument.', $output );
    }

    if ( !is_reseller_without_domain( username => $username ) ) {
        return ( 0, 'The supplied user either does not exist or is not a reseller without a domain.', $output );
    }

    eval {
        # also handles homedir removal
        Cpanel::SysAccounts::remove_system_user($username);

        # Private _unsetupreseller does what we need in this case
        Whostmgr::Resellers::Setup::_unsetupreseller($username);

        _delete_user_file($username);

        Cpanel::AcctUtils::AccountingLog::append_entry( "REMOVERESELLERWITHOUTDOMAIN", [$username] );
    };
    if ( my $exception = $@ ) {
        return ( 0, Cpanel::Exception::get_string($exception), $output );
    }

    return (
        1,
        'OK',
        $output,
    );
}

=head2 _delete_user_file()

Private implementation

=cut

sub _delete_user_file ($username) {
    my $cpuser_file = "$Cpanel::ConfigFiles::cpanel_users/$username";
    return unlink $cpuser_file;
}

=head1 SEE ALSO

=over

=item * WHM API 1 createacct reseller_without_domain=1

=item * Whostmgr::Accounts::Create::ResellerWithoutDomain

=item * https://go.cpanel.net/how-to-create-a-whm-reseller-without-an-associated-domain

=back

=cut

1;
