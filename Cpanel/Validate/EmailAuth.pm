package Cpanel::Validate::EmailAuth;

# cpanel - Cpanel/Validate/EmailAuth.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#use warnings; #not for production -- passes
#use strict;  #not for production  -- passes
use Cpanel::StringFunc::Case                 ();
use Cpanel::StringFunc::Trim                 ();
use Cpanel::Validate::EmailLocalPart         ();
use Cpanel::Email::Normalize::EmailLocalPart ();

# From discussions in Case 30822, and discussion after 31578
#   Supported separators [+:%@]
#   All characters from RFC 5322 (also 2822 and 822) are supported except for
#   the separator character and characters that conflict with creating directories
#   and such. See Cpanel::Validate::Email::LocalPart for the allowed characters.
#   We do not support the quoted string format, however.
#   The domain part of the email address is as described in RFC 1035 and 5321,
#   except the parts of the domain name can begin and end with digits. This
#   matches actual usage.
sub is_valid {
    my ($name) = @_;
    return unless defined $name;

    # See EmailLocalPart for a description of how it varies from the RFCs
    # In order to support email addresses as usernames, the allowed separators
    #   between local part and domain are [+%:@].
    # In order to support actual domains in the wild, we allow leading and
    #   trailing digits in the domain parts. This violates the relavant RFCs.
    my ( $local, $domain ) = get_name_and_domain($name);
    return unless defined $local and defined $domain;
    return Cpanel::Validate::EmailLocalPart::is_valid($local) && is_domain_valid($domain);
}

sub normalize {
    my ($name) = @_;
    return unless defined $name;
    $name =~ s/\0//g;

    $name = Cpanel::StringFunc::Trim::ws_trim($name);
    $name =~ s/[+%:]([^+%:@]+)$/\@$1/ unless $name =~ /\@/;
    my ( $local, $domain ) = get_name_and_domain($name);
    return $name unless defined $local and defined $domain;
    $local  = Cpanel::Email::Normalize::EmailLocalPart::normalize($local);
    $domain = Cpanel::StringFunc::Case::ToLower($domain);
    return "$local\@$domain";
}

sub get_name_and_domain {
    my ($name) = @_;
    return unless defined $name;
    my ( $local, $domain ) = split( /\@/, $name, 2 );
    return ( $local ? $local : undef, $domain ? $domain : undef );
}

sub has_email_separator {
    my ($str) = @_;
    return scalar $str =~ /[+:%@]/;
}

sub is_domain_valid {
    my ($domain) = @_;
    return unless defined $domain;
    return scalar $domain =~ m/\A[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?(?:\.[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?)*\z/;
}

sub scrub {
    my ($name) = @_;
    return unless defined $name;
    $name = normalize($name);
    my ( $user, $domain ) = get_name_and_domain($name);
    return unless defined $user and defined $domain;
    $user = Cpanel::Email::Normalize::EmailLocalPart::scrub($user);

    # ? Cpanel::DomainTools ?
    $domain = Cpanel::StringFunc::Case::ToLower($domain);
    $domain =~ tr/a-z0-9\-.//cd;
    $domain =~ s/\.+/./g;
    return "$user\@$domain";
}

1;
