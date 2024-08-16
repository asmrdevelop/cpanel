package Cpanel::AcctUtils::Lookup::MailUser::Exists;

# cpanel - Cpanel/AcctUtils/Lookup/MailUser/Exists.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Lookup::Webmail ();
use Cpanel::AcctUtils::Account         ();
use Cpanel::Autodie ('exists');
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::PwCache                      ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Validate::EmailCpanel        ();
use Cpanel::Exception                    ();

=encoding utf-8

=head1 NAME

Cpanel::AcctUtils::Lookup::MailUser::Exists - Utilities for determining if a mail account exists on this system.

=head1 SYNOPSIS

    use Cpanel::AcctUtils::Lookup::MailUser::Exists ();

    my $exists = Cpanel::AcctUtils::Lookup::MailUser::Exists::does_mail_user_exist('bob@bob.org');

=head2 does_mail_user_exist($user)

If the user has a mail account on this system, this function
returns 1.  If the user does not have a mail account on this system,
this function returns 0.

This function can accept full email addresses such as
“localpart@domain.tld”, logins such as
“localpart%domain.tld”, and system users such as “user”.

=cut

sub does_mail_user_exist {
    my ($user) = @_;
    if ( !Cpanel::AcctUtils::Lookup::Webmail::is_webmail_user($user) ) {
        return Cpanel::AcctUtils::Account::accountexists($user);
    }
    my ( $subuser, $domain ) = Cpanel::AcctUtils::Lookup::Webmail::normalize_webmail_user($user);

    Cpanel::Validate::FilesystemNodeName::validate_or_die($domain);
    Cpanel::Validate::FilesystemNodeName::validate_or_die($subuser);

    # Ensuring this is a valid email address based on internal cpanel usage
    if ( !Cpanel::Validate::EmailCpanel::is_valid($user) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid account name.', [$user] );
    }

    my $domainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, { 'skiptruelookup' => 1, 'default' => '' } );
    return 0 if !$domainowner;

    my $ownerhomedir = Cpanel::PwCache::gethomedir($domainowner);

    return Cpanel::Autodie::exists("$ownerhomedir/mail/$domain/$subuser");
}

1;
