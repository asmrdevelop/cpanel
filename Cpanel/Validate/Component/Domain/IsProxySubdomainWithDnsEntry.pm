package Cpanel::Validate::Component::Domain::IsProxySubdomainWithDnsEntry;

# cpanel - Cpanel/Validate/Component/Domain/IsProxySubdomainWithDnsEntry.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base qw ( Cpanel::Validate::Component );

use Cpanel::Config::LoadCpConf      ();
use Cpanel::Config::WebVhosts       ();
use Cpanel::Config::userdata::Utils ();
use Cpanel::DnsUtils::AskDnsAdmin   ();
use Cpanel::Exception               ();
use Cpanel::Proxy::Tiny             ();
use Cpanel::Config::userdata::Load  ();

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain target_domain ));
    $self->add_optional_arguments(qw( ownership_user force proxysubdomains proxysubdomainsoverride ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    if ( !defined $self->{'proxysubdomains'} || !defined $self->{'proxysubdomainsoverride'} ) {
        my $cpanel_config_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        $self->{'proxysubdomains'}         = ( !exists $cpanel_config_ref->{'proxysubdomains'} || $cpanel_config_ref->{'proxysubdomains'} ) ? 1                                                           : 0;
        $self->{'proxysubdomainsoverride'} = exists $cpanel_config_ref->{'proxysubdomainsoverride'}                                         ? ( $cpanel_config_ref->{'proxysubdomainsoverride'} ? 1 : 0 ) : 1;
    }

    $self->{'force'} = 0 if !$self->{'force'};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $domain, $target_domain, $user, $force, $proxy_subdomains, $proxy_subdomains_override ) = @{$self}{ $self->get_validation_arguments() };

    if ($proxy_subdomains) {
        my $proxy_subdomains_hr = Cpanel::Proxy::Tiny::get_known_proxy_subdomains();

        if ( grep { $domain eq "$_.$target_domain" } sort keys %$proxy_subdomains_hr ) {
            if ($proxy_subdomains_override) {
                $force = 1;
            }
            elsif ( !$force ) {
                die Cpanel::Exception::create(
                    'ProxySubdomainConflict',
                    'The supplied subdomain name, [_1], conflicts with an existing service subdomain.',
                    [$domain],
                );
            }
        }
    }

    # Allow the upgrade of mail.domain.tld to an actual domain if they own the base domain
    if ( !$force && $user && index( $domain, 'mail.' ) == 0 ) {
        my $match_domain = substr( $domain, 5 );

        my $wvh        = Cpanel::Config::WebVhosts->load($user);
        my $vhost_name = $wvh->get_vhost_name_for_domain($domain) or die "“$user” has no web vhost for “$domain”!";

        my $vh_conf = Cpanel::Config::userdata::Load::load_userdata_domain_or_die( $user, $vhost_name );

        $force = grep { $_ eq $match_domain } Cpanel::Config::userdata::Utils::get_all_vhost_domains_from_vhost_userdata($vh_conf);
    }

    # This is unfortunately tied to the service (formerly proxy) subdomain code above, which is why it isn't in its own module.
    # If the subdomain conflicts with a service (formerly proxy) subdomain, but proxysubdomainsoverride is enabled, we need to skip this check
    if ( !$force && Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'ZONEEXISTS', 0, $domain ) ) {
        die Cpanel::Exception::create( 'DnsEntryAlreadyExists', "A DNS entry for the domain “[_1]” already exists.", [$domain] );
    }

    return;
}

1;
