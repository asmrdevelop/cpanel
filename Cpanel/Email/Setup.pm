package Cpanel::Email::Setup;

# cpanel - Cpanel/Email/Setup.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hostname   ();
use Cpanel::LoadModule ();

#########################################################################
#
# Method:
#   get_account_properties
#
# Description:
#   Returns the properties of a given email account such as
#   organization, displayname, etc that can be used to configure
#   access to the account.
#
# Parameters:
#
#   account           - An email account [string]
#   (required)
#
#   use_ssl           - Return secure or insecure properties [boolean]
#   (required)
#
# Returns:
#   A hashref of properties about the account like:
#   {
#     'emailid'     => 'bob.cpanel.com',
#     'is_archive'  => 0,
#     'email'       => 'bob@cpanel.net',
#     'organization'=> 'cpanel.com',
#     'displayname' => 'bob@cpanel.net Secure Email Archive Setup',
#   }
#

sub get_account_properties {
    my ( $account, $use_ssl ) = @_;

    my $email   = $account =~ m{@} ? $account : "$account\@" . Cpanel::Hostname::gethostname();
    my $emailid = $email;
    $emailid =~ s{\@}{\.}g;
    my $organization = ( split( m{@}, $email ) )[-1];
    my $is_archive   = $email =~ m{^_archive\@} ? 1 : 0;

    Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
    my $locale      = Cpanel::Locale->get_handle();
    my $displayname = $is_archive ? $organization : $email;
    if ($use_ssl) {
        $displayname .= ' ' . ( $is_archive ? $locale->maketext('Secure Email Archive Setup') : $locale->maketext('Secure Email Setup') );
    }
    else {
        $displayname .= ' ' . ( $is_archive ? $locale->maketext('Email Archive Setup') : $locale->maketext('Email Setup') );
    }

    return {
        'emailid'      => $emailid,
        'is_archive'   => $is_archive,
        'email'        => $email,
        'organization' => $organization,
        'displayname'  => $displayname
    };
}
1;
