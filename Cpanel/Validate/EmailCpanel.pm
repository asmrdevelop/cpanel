package Cpanel::Validate::EmailCpanel;

# cpanel - Cpanel/Validate/EmailCpanel.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Validate::EmailLocalPart ();
use Cpanel::WildcardDomain::Tiny     ();

# From discussions in Case 30822, and discussion after 31578
#   Supported separator: @
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
    # In order to support actual domains in the wild, we allow leading and
    #   trailing digits in the domain parts. This violates the relavant RFCs.
    my ( $local, $domain ) = get_name_and_domain($name);
    return unless defined $local and defined $domain;
    return Cpanel::Validate::EmailLocalPart::is_valid($local) && is_domain_valid($domain);
}

sub get_name_and_domain {
    my ($name) = @_;
    return unless defined $name;
    my ( $local, $domain ) = split( /\@/, $name, 2 );
    return ( length $local ? $local : undef, length $domain ? $domain : undef );
}

sub has_email_separator {
    my ($str) = @_;
    return scalar $str =~ /\@/;
}

sub is_domain_valid {
    my ($domain) = @_;
    return unless defined $domain;
    return 0 if Cpanel::WildcardDomain::Tiny::is_wildcard_domain($domain);
    return scalar $domain =~ m/\A[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?(?:\.[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?)*\z/;
}

1;
