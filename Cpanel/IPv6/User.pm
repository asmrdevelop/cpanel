package Cpanel::IPv6::User;

# cpanel - Cpanel/IPv6/User.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpUserFile  ();
use Cpanel::Config::userdata::Load  ();
use Cpanel::IPv6::Normalize         ();
use Cpanel::IPv6::UserDataUtil::Key ();

=encoding utf-8

=head1 NAME

Cpanel::IPv6::User - Tools for looking up IPv6 data for a user

=head1 SYNOPSIS

    use Cpanel::IPv6::User;

    my($ok,$ipv6) = Cpanel::IPv6::User::get_user_ipv6_address($user, $domain);

    my $ip = Cpanel::IPv6::User::extract_ipv6_from_userdata($userdata);

=cut

=head2 get_user_ipv6_address($user,$domain)

Returns two arguments.

The first arguments is 0 or 1 depending on if the user's domain has an
ipv6 address.

If the user's domain has an ipv6 address, the second
argument is the ipv6 address 

=cut

sub get_user_ipv6_address {
    my ( $user, $domain ) = @_;

    my $cpuser_hr;
    $domain ||= ( $cpuser_hr ||= Cpanel::Config::LoadCpUserFile::load($user) )->{'DOMAIN'};

    # Load the data file for the main domain (no need to guard this as its read only)
    my $data = Cpanel::Config::userdata::Load::load_userdata_domain( $user, $domain, $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP );

    my $ip = extract_ipv6_from_userdata($data) || ( $cpuser_hr ||= Cpanel::Config::LoadCpUserFile::load($user) )->{'IPV6'};

    my ( $ok, $ipv6 ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($ip);

    return ( $ok, $ipv6 ) if $ok;

    return ( 0, Cpanel::IPv6::Normalize::DOES_NOT_HAVE_IPV6_STRING() );    # Cpanel::IPv6::Normalize::DOES_NOT_HAVE_IPV6_STRING() is a magical return that is required
}

=head2 extract_ipv6_from_userdata($userdata)

Get the IPv6 address out of the userdata
returns an IPv6 address or undef if there is not IPv6 address to be found

=cut

sub extract_ipv6_from_userdata {
    my ($data) = @_;

    return unless ( ref $data eq 'HASH' and ref $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} eq 'HASH' );
    return ( keys %{ $data->{$Cpanel::IPv6::UserDataUtil::Key::ipv6_key} } )[0];
}

1;
