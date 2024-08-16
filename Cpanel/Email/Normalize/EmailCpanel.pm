package Cpanel::Email::Normalize::EmailCpanel;

# cpanel - Cpanel/Email/Normalize/EmailCpanel.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Validate::EmailCpanel            ();
use Cpanel::Email::Normalize::EmailLocalPart ();
use Cpanel::StringFunc::Trim                 ();
use Cpanel::StringFunc::Case                 ();

sub normalize {
    my ($name) = @_;
    return unless defined $name;
    $name =~ s/\0//g;

    $name = Cpanel::StringFunc::Trim::ws_trim($name);
    my ( $local, $domain ) = Cpanel::Validate::EmailCpanel::get_name_and_domain($name);
    return $name unless defined $local and defined $domain;
    $local  = Cpanel::Email::Normalize::EmailLocalPart::normalize($local);
    $domain = Cpanel::StringFunc::Case::ToLower($domain);
    return "$local\@$domain";
}

sub scrub {
    my ($name) = @_;
    return unless defined $name;
    $name = normalize($name);
    my ( $user, $domain ) = Cpanel::Validate::EmailCpanel::get_name_and_domain($name);
    return unless defined $user and defined $domain;
    $user = Cpanel::Email::Normalize::EmailLocalPart::scrub($user);

    # ? Cpanel::DomainTools ?
    $domain = Cpanel::StringFunc::Case::ToLower($domain);
    $domain =~ tr/a-z0-9\-.//cd;
    $domain =~ s/\.+/./g;
    return "$user\@$domain";
}

1;
