package Cpanel::UserDomainIp;

# cpanel - Cpanel/UserDomainIp.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::UserDomainIp - Which IPv4 address does httpd use for this domain?

=head1 SYNOPSIS

    my $ipv4_addr = Cpanel::UserDomainIp::getdomainip($domain);

=head1 DESCRIPTION

Ordinarily it should be trivial for a user to determine which IPv4 address,
if any, httpd uses to host a given domain’s web content: a cPanel user can
only have one assigned IPv4 address, so by definition all web content should
be hosted from that IPv4 address.

We unofficially, though, support having a single user host web content on
multiple IP addresses concurrently by tweaking their web vhost configuration
files (i.e., F</var/cpanel/userdata>).

This module, then, implements logic that allows an unprivileged user to
determine which IPv4 address httpd uses to host web content for a given domain.

=cut

use Cpanel::Config::userdata::Load ();
use Cpanel::PwCache                ();

my %DOMAINIPCACHE;

our $VERSION = '1.4';

=head1 FUNCTIONS

=head2 $ip_addr = getdomainip( $DOMAIN_NAME )

Returns the IPv4 address that httpd uses to host $DOMAIN_NAME’s web content.

Returns undef if there is no such domain in the user’s web vhost
configuration.

If you’re running as root but want to query for a specific user, then set
C<$Cpanel::user> prior to calling this function.

=cut

sub getdomainip {
    return _getdomainip( 'load_userdata_domain', @_ );
}

=head2 $ip_addr = getdomainip_ssl( $DOMAIN_NAME )

Similar to C<getdomainip()> but for SSL web vhosts.

=cut

sub getdomainip_ssl {
    return _getdomainip( 'load_ssl_domain_userdata', @_ );
}

#----------------------------------------------------------------------

sub _getdomainip {
    my ( $fn, $dns ) = @_;

    if ( !length $dns ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create_raw("getdomainip requires a domain.");
    }

    return $DOMAINIPCACHE{$dns} //= do {
        my $username = $Cpanel::user || Cpanel::PwCache::getusername();

        my $load_cr = Cpanel::Config::userdata::Load->can($fn);

        my $domain_data = $load_cr->(
            $username,
            $dns,
            $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP,
        );

        if ( !$domain_data || !%$domain_data ) {
            require Cpanel::Config::WebVhosts;
            my $wvh = Cpanel::Config::WebVhosts->load($username);

            if ( my $vh_name = $wvh->get_vhost_name_for_domain($dns) ) {
                $domain_data = $load_cr->(
                    $username,
                    $vh_name,
                    $Cpanel::Config::userdata::Load::ADDON_DOMAIN_CHECK_SKIP,
                );
            }
        }

        $domain_data && $domain_data->{'ip'};
    };
}

1;
