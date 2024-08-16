package Cpanel::AccessControl;

# cpanel - Cpanel/AccessControl.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# NB: Can’t use signatures here because of updatenow.

=encoding utf-8

=head1 NAME

Cpanel::AccessControl

=head1 DESCRIPTION

This module contains logic to authorize one user’s access to another.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception                  ();
use Cpanel::Reseller                   ();
use Cpanel::AcctUtils::Lookup          ();
use Cpanel::AcctUtils::Lookup::Webmail ();
use Cpanel::AcctUtils::Owner           ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 verify_user_access_to_account($USERNAME, $SPECIMEN_USERNAME)

This function intends to validate that:

=over

=item * $USERNAME is a cPanel username.

=item * $SPECIMEN_USERNAME is a cPanel or email-subaccount username.

=item * $USERNAME is authorized to act on behalf of $SPECIMEN_USERNAME.

=back

If any of the above assertions is false,
L<Cpanel::Exception::UserNotFound> is thrown.

=cut

sub verify_user_access_to_account {
    my ( $cpusername, $specimen_username ) = @_;

    # This returns truthy as long as the user controls the domain,
    # even if the account doesn’t actually exist. It’ll also
    # throw if the domain doesn’t exist. That’s why we also
    # check for existence of the email account.
    my $is_ok = user_has_access_to_account( $cpusername, $specimen_username );

    $is_ok &&= do {
        require Cpanel::AcctUtils::Lookup::MailUser::Exists;
        Cpanel::AcctUtils::Lookup::MailUser::Exists::does_mail_user_exist($specimen_username);
    };

    if ( !$is_ok ) {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $specimen_username ] );
    }

    return;
}

#NOTE: This combines two different kinds of authz checks:
#   - reseller-to-cpuser ownership
#   - cpuser-to-email ownership
#
#Anything the cpuser can access, that cpuser’s reseller-owner can
#also access.
#
#XXX XXX XXX: This does NOT care about whether an email account actually
#exists on the system!!! It is VERY likely that you should call
#Cpanel::AcctUtils::Lookup::MailUser::Exists::does_mail_user_exist() in tandem
#with this function. XXX XXX XXX
#
sub user_has_access_to_account {
    my ( $user_requesting_access, $account ) = @_;

    # May always access them selves
    if ( $user_requesting_access eq $account ) {
        return 1;
    }

    # And if they have root they may
    elsif ( Cpanel::Reseller::hasresellerpriv( $user_requesting_access, 'all' ) ) {
        return 1;
    }
    else {
        my $cpanel_account_owner;

        if ( Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($account) ) {    #webmail user
                                                                                         # This may generate an exception for an invalid user
            my $webmail_accounts_cpanel_user = Cpanel::AcctUtils::Lookup::get_system_user($account);

            # If they own the email account they may
            if ( $webmail_accounts_cpanel_user && $user_requesting_access eq $webmail_accounts_cpanel_user ) {
                return 1;
            }
            $cpanel_account_owner = Cpanel::AcctUtils::Owner::getowner($webmail_accounts_cpanel_user);
        }
        else {
            $cpanel_account_owner = Cpanel::AcctUtils::Owner::getowner($account);
        }

        # If they are the reseller that owns the cpanel account or the reseller that
        # owns cpanel account for the webmail user.
        if ( $cpanel_account_owner && $user_requesting_access eq $cpanel_account_owner ) {
            return 1;
        }
    }

    return 0;
}

1;
