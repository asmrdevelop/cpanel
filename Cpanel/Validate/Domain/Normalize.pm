package Cpanel::Validate::Domain::Normalize;

# cpanel - Cpanel/Validate/Domain/Normalize.pm       Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug                  ();
use Cpanel::StringFunc::Trim       ();
use Cpanel::Encoder::Punycode      ();
use Cpanel::Validate::Domain::Tiny ();

our $VERSION = '1.0';

=encoding utf-8

=head1 NAME

Cpanel::Validate::Domain::Normalize - Normalize domain name input.

=head1 SYNOPSIS

    use Cpanel::Validate::Domain::Normalize;

    my $domain = Cpanel::Validate::Domain::Normalize::normalize('cPaNeL.NeT');

=head2 normalize($domain, $quiet)

Takes input that looks like a domain and returns a normalized
version which is all lowercase, trims whitespace, and applies
punycode encoding.

If $domain is undefined, this returns nothing.

If $quiet is not passed, this also checks validity of the normalized
domain and, if the domain isn’t valid, creates an info-level log message.

=cut

sub normalize {
    my ( $domain, $quiet ) = @_;
    if ( !defined $domain ) {
        return;
    }

    $domain = _just_normalize($domain);

    if ( !$quiet && !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
        Cpanel::Debug::log_info("Invalid domain $domain specified.");
    }

    return $domain;
}

=head2 normalize_wildcard($domain)

This function is mostly redundant with C<normalize($domain, 1)>,
but if $domain is empty an exception is thrown.

This does NOT validate the wildcard.
If you want that, take the output of this function,
and run it through Cpanel::Validate::Domain::validwildcarddomain().

=cut

sub normalize_wildcard {
    my ($domain) = @_;

    die "Domain is missing!" if !length $domain;

    return _just_normalize($domain);
}

=head2 normalize_to_root_domain($domain, $quiet)

Like C<normalize()> but also strips any prefixes (such as "*") to produce a root
domain. While this strips all "www" components now, it may not in the future
if we choose to allow e.g. www.co.uk.

=cut

sub normalize_to_root_domain {
    my ( $domain, $quiet ) = @_;

    return undef unless defined $domain;

    $domain = normalize( $domain, $quiet );

    substr( $domain, 0, 2, '' ) if rindex( $domain, '*.',   0 ) == 0;
    substr( $domain, 0, 4, '' ) if rindex( $domain, 'www.', 0 ) == 0;

    return $domain;
}

sub _just_normalize {
    my ($domain) = @_;
    Cpanel::StringFunc::Trim::ws_trim( \$domain );

    $domain =~ tr{A-Z}{a-z};

    # If $domain is normal ascii or punycode already it will not be modified
    return Cpanel::Encoder::Punycode::punycode_encode_str($domain);
}

1;
