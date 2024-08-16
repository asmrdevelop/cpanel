package Cpanel::Validate::EmailRFC;

# cpanel - Cpanel/Validate/EmailRFC.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module does NOT match the logic of CPAN’s Email::Address.
# (For example, “qwe@qwe” validates as per E::A, but not here.)
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::StringFunc::Case     ();
use Cpanel::StringFunc::Trim     ();
use Cpanel::WildcardDomain::Tiny ();

# From discussions in Case 30822, and discussion after 31578
#   Supported separator: @
#   All characters from RFC 5322 (also 2822 and 822) are supported in the
#   local part of the address. We do not support the quoted string format, however.
#   The domain part of the email address is as described in RFC 1035 and 5321,
#   except the parts of the domain name can begin and end with digits. This
#   matches actual usage.
sub is_valid {
    my ($name) = @_;
    return if !defined $name || index( $name, '@' ) == -1;

    my ( $local, $domain ) = get_name_and_domain($name);
    return unless defined $local and defined $domain;
    return is_localpart_valid($local) && is_domain_valid($domain);
}

sub is_valid_remote {
    my ($name) = @_;
    return if !defined $name || index( $name, '@' ) == -1;

    my ( $local, $domain ) = get_name_and_domain($name);
    return unless defined $local and defined $domain;
    return is_localpart_valid($local) && is_domain_valid_remote($domain);
}

# Throws Cpanel::Exception::InvalidParameter
sub is_valid_remote_or_die {
    my ($name) = @_;

    if ( !is_valid_remote($name) ) {
        local ( $@, $! );
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid email address.', [$name] );
    }

    return;
}

sub normalize {
    my ($name) = @_;
    return unless defined $name;
    $name =~ s/\0//g;

    $name = Cpanel::StringFunc::Trim::ws_trim($name);
    $name = Cpanel::StringFunc::Case::ToLower($name);

    return $name;
}

sub get_name_and_domain {
    my ($name) = @_;
    return unless defined $name;
    my ( $local, $domain ) = split( /\@/, $name, 2 );
    return ( $local ? $local : undef, $domain ? $domain : undef );
}

sub has_email_separator {
    my ($str) = @_;
    return scalar $str =~ /\@/;
}

sub is_localpart_valid {
    my ($local) = @_;
    return if !length $local;
    return $local =~ m/
        \A
        [a-zA-Z0-9!#\$%&'*+\-\/=?^_`{|}~]+
        (?:
            \.
            [a-zA-Z0-9!#\$%&'*+\-\/=?^_`{|}~]+
        )*
        \z
    /x;
}

sub is_domain_valid {
    my ($domain) = @_;
    return unless defined $domain;
    return 0 if Cpanel::WildcardDomain::Tiny::is_wildcard_domain($domain);
    return scalar $domain =~ m/
        \A
        [0-9a-zA-Z]
        (?:
            [0-9a-zA-Z-]*
            [0-9a-zA-Z]
        )?
        (?:
            \.
            [0-9a-zA-Z]
            (?:
                [0-9a-zA-Z-]*
                [0-9a-zA-Z]
            )?
        )*
        \z
    /x;
}

sub is_domain_valid_remote {
    my ($domain) = @_;
    return unless defined $domain;

    # The regex catches localhost plus 'domains' with only one part.
    return unless scalar $domain =~ m/
        \A
        [0-9a-zA-Z]
        (?:
            [0-9a-zA-Z-]*
            [0-9a-zA-Z]
        )?
        (?:
            \.
            [0-9a-zA-Z]
            (?:
                [0-9a-zA-Z-]*
                [0-9a-zA-Z]
            )?
        )+
        \z
    /x;

    return Cpanel::StringFunc::Case::ToLower($domain) ne 'localhost.localdomain';
}

sub scrub {
    my ($name) = @_;
    return unless defined $name;
    $name = normalize($name);
    $name =~ s/\.\.+/./g;
    my ( $user, $domain ) = get_name_and_domain($name);
    return unless defined $user and defined $domain;
    $user =~ tr/a-z0-9!#$%&'*+\-\/=?^_`{|}~.//cd;

    # ? Cpanel::DomainTools ?
    $domain =~ tr/a-z0-9\-.//cd;
    return "$user\@$domain";
}

1;
