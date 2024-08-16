package Cpanel::Security::Authn::Webmail;

# cpanel - Cpanel/Security/Authn/Webmail.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::Webmail

=head1 SYNOPSIS

    # This returns more than just the password; see below.
    my ($encrypted_pw) = fetch_mail_user_encrypted_password($localpart, $domain, $homedir);

=head1 DESCRIPTION

This module encapsulates logic to fetch a Webmail user’s encrypted
password.

=cut

#----------------------------------------------------------------------

use Cpanel::AcctUtils::Lookup::MailUser ();

# Referenced in tests.
use constant _CPSRVD_PATH => '/usr/local/cpanel/cpsrvd';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($pw, $mtime, $chg_time, $strength) = fetch_mail_user_encrypted_password($LOCALPART, $DOMAIN, $HOMEDIR)

Fetches an indicated Webmail user’s encrypted password.

The $LOCALPART and $DOMAIN inputs specify the Webmail account. $HOMEDIR is
the cPanel user’s system home directory.

This returns a list:

=over

=item * The encrypted password, if one was found. (This is undef otherwise.)

=item * The modification time, in epoch seconds, of either the $DOMAIN’s
shadow file or cpsrvd itself, whichever is later.

=item * The time, in epoch seconds, when the password was last updated.
(This is undef if no encrypted password was found.)

=item * The password’s strength, if it is available. (This is undef otherwise.)

=back

=cut

sub fetch_mail_user_encrypted_password ( $localpart, $domain, $homedir ) {

    # Although fetch_mail_user_encrypted_password takes a $homedir
    # argument, lookup_mail_user doesn't currently support passing the $homedir
    # to avoid the lookup, however since we may use it later it was
    # kept as an argument
    my $response          = Cpanel::AcctUtils::Lookup::MailUser::lookup_mail_user_or_die( $localpart . '@' . $domain );
    my $user_info         = $response->{user_info};
    my $crypted_pass      = $user_info->{shadow}{user};
    my $passwd_file_mtime = $user_info->{passwd}{mtime};
    my $lastchanged       = $user_info->{passwd}{pass_change_time};
    my $pwstrength        = $user_info->{passwd}{strength};
    return ( $crypted_pass, $passwd_file_mtime, $lastchanged, $pwstrength );
}

1;
