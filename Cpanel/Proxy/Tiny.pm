package Cpanel::Proxy::Tiny;

# cpanel - Cpanel/Proxy/Tiny.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpConf                  ();
use Cpanel::WebVhosts::AutoDomains              ();
use Cpanel::Server::Type::Role::Webmail         ();
use Cpanel::Server::Type::Role::WebDisk         ();
use Cpanel::Server::Type::Role::CalendarContact ();

our $DEFAULT_AUTODISCOVERY_HOST = 'cpanelemaildiscovery.cpanel.net';

=encoding utf-8

=head1 NAME

Cpanel::Proxy::Tiny - Subset of functions from Cpanel::Proxy

=head1 SYNOPSIS

    use Cpanel::Proxy::Tiny;

    my $known_proxy_subdomains_ref = Cpanel::Proxy::Tiny::get_known_proxy_subdomains();

=cut

=head2 get_known_proxy_subdomains( \%OPTS )

Returns a list of known service (formerly proxy) subdomains and the type
of domains they are assoicated with.

%OPTS are:

=over

=item * C<include_disabled> - Whether to include all subdomains that
otherwise would be omitted because of system configuration.

=item * C<force_autodiscover_support> - Like C<include_disabled> but
applies only to C<autoconfig> and C<autodiscover> subdomains.

=back

If force_autodiscover_support is set to 1 in the hashref,
the autoconfig and autodiscover service (formerly proxy) subdomains will
be in the output even if they are disabled on this system.

Example Output:

{
  'autoconfig' => {
                    'domains' => 'all'
                  },
  'cpcontacts' => {
                    'domains' => 'all'
                  },
   ...
}

=cut

sub get_known_proxy_subdomains {
    my $opts = shift || {};

    my %known_proxy_subdomains = map { $_ => { domains => 'all' } } Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_PROXIES();

    if ( !$opts->{'include_disabled'} ) {
        my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

        if ( !$opts->{'force_autodiscover_support'} && !$cpconf_ref->{'autodiscover_proxy_subdomains'} ) {
            delete $known_proxy_subdomains{'autoconfig'};
            delete $known_proxy_subdomains{'autodiscover'};
        }

        if ( !Cpanel::Server::Type::Role::Webmail->is_enabled() ) {
            delete $known_proxy_subdomains{'webmail'};
        }

        if ( !Cpanel::Server::Type::Role::WebDisk->is_enabled() ) {
            delete $known_proxy_subdomains{'webdisk'};
        }

        if ( !Cpanel::Server::Type::Role::CalendarContact->is_enabled() ) {
            delete $known_proxy_subdomains{'cpcontacts'};
            delete $known_proxy_subdomains{'cpcalendars'};
        }
    }

    return \%known_proxy_subdomains;
}

1;
