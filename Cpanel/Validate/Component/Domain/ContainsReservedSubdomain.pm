package Cpanel::Validate::Component::Domain::ContainsReservedSubdomain;

# cpanel - Cpanel/Validate/Component/Domain/ContainsReservedSubdomain.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::WebVhosts::AutoDomains ();
use Cpanel::DnsUtils::AskDnsAdmin  ();
use Cpanel::Exception              ();

use base qw ( Cpanel::Validate::Component );

sub init {
    my ( $self, %OPTS ) = @_;

    $self->add_required_arguments(qw( domain target_domain ));
    $self->add_optional_arguments(qw( only_if_exists ));
    my @validation_arguments = $self->get_validation_arguments();
    @{$self}{@validation_arguments} = @OPTS{@validation_arguments};

    return;
}

sub validate {
    my ($self) = @_;

    $self->validate_arguments();

    my ( $domain, $target_domain, $only_if_exists ) = @{$self}{ $self->get_validation_arguments() };

    # Should this determine the service (formerly proxy) subdomains based upon cpanel.config settings?
    my $regex = Cpanel::WebVhosts::AutoDomains::all_possible_proxy_subdomains_regex();
    if ( $domain =~ m/^(www|mail|ftp|$regex)\.\Q${target_domain}\E$/i ) {
        my $reserved = $1;

        # Only check if the zone exists if we match the regex which should be rare
        # since a zone exists check is far more expensive
        return if $only_if_exists && !Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'ZONEEXISTS', 0, $domain );
        #
        die Cpanel::Exception::create( 'ReservedSubdomain', 'The domain “[_1]” contains a reserved subdomain, [_2], that is already in use. This subdomain may not be used here.', [ $domain, $reserved ] );
    }

    return;
}

1;
