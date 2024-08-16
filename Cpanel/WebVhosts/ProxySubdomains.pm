package Cpanel::WebVhosts::ProxySubdomains;

# cpanel - Cpanel/WebVhosts/ProxySubdomains.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::WebVhosts::ProxySubdomains - service (formerly proxy) subdomains & vhosts

=head1 SYNOPSIS

    #This takes account of both system configuration and the user’s
    #reseller status. It does NOT account for any particular vhosts;
    #this is just a list of labels that the system will add as
    #SSL service (formerly proxy) subdomains for a given DNS zone if (and only if)
    #the given subdomain/zone combination isn’t already in action
    #otherwise in the user’s vhost setup.
    my @labels = Cpanel::WebVhosts::ProxySubdomains::ssl_proxy_subdomain_labels_for_user('johnny');

    #Call this function after creating or removing a domain, and if
    #$operand_domain is an override of a service (formerly proxy) subdomain, it’ll recreate
    #the vhost for the base of that service (formerly proxy) subdomain.
    #
    #   Example: operand domain is “cpanel.mydomain.tld”. This function will
    #   recreate the vhost for “mydomain.tld”.
    Cpanel::WebVhosts::ProxySubdomains::sync_base_vhost_if_needed('johnny', $operand_domain);

=cut

use Cpanel::Context                             ();
use Cpanel::Reseller                            ();
use Cpanel::Config::LoadCpConf                  ();
use Cpanel::WebVhosts::AutoDomains              ();
use Cpanel::Server::Type::Role::Webmail         ();
use Cpanel::Server::Type::Role::WebDisk         ();
use Cpanel::Server::Type::Role::CalendarContact ();

our $_has_webmail_role;
our $_has_webdisk_role;
our $_has_calendar_role;

sub ssl_proxy_subdomain_labels_for_user {
    my ($user) = @_;

    die 'Need user!' if !length $user;

    Cpanel::Context::must_be_list();

    my $cpconf = _cpconf();

    #This check is a bit superfluous, but it doesn’t hurt anything
    #and might prevent bugs down the line.
    return if !$cpconf->{'proxysubdomains'};

    return (
        Cpanel::WebVhosts::AutoDomains::PROXIES_FOR_EVERYONE(),
        ( ( $_has_webmail_role //= Cpanel::Server::Type::Role::Webmail->is_enabled() )          ? 'webmail'                  : () ),
        ( ( $_has_webdisk_role //= Cpanel::Server::Type::Role::WebDisk->is_enabled() )          ? 'webdisk'                  : () ),
        ( ( $_has_calendar_role //= Cpanel::Server::Type::Role::CalendarContact->is_enabled() ) ? qw{cpcontacts cpcalendars} : () ),
        ( $cpconf->{'autodiscover_proxy_subdomains'}                                            ? 'autodiscover'             : () ),
        ( _is_reseller($user)                                                                   ? 'whm'                      : () ),
    );
}

sub sync_base_vhost_if_needed {
    my ( $username, $operand_domain ) = @_;

    my ( $label, $base_domain ) = split m<\.>, $operand_domain, 2;

    if ( -1 != index( $base_domain, '.' ) ) {
        my @proxy_labels = ssl_proxy_subdomain_labels_for_user($username);

        if ( grep { $label eq $_ } @proxy_labels ) {
            require Cpanel::ConfigFiles::Apache::vhost;

            #overridden in tests
            Cpanel::ConfigFiles::Apache::vhost::update_domains_vhosts($base_domain);

            return 1;
        }
    }

    return 0;
}

#overridden in tests
*_is_reseller = \&Cpanel::Reseller::isreseller;

#overridden in tests
*_cpconf = *Cpanel::Config::LoadCpConf::loadcpconf_not_copy;

1;
