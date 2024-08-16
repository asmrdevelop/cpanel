package Cpanel::Services::Uri;

# cpanel - Cpanel/Services/Uri.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception       ();
use Cpanel::Services::Ports ();
use Cpanel::SSL::Domain     ();

my $ssl_host;

=head1 NAME

Cpanel::Services::Uri

=head1 DESCRIPTION

A module to contain the functions in getting or dealing with a cPanel service (cpaneld, whostmgrd, webmaild) URI.

=head2 get_service_ssl_base_uri_by_service_name

=head3 Purpose

   Gets the best SSL enabled URI for a passed in service. This function determines the best SSL domain for the
   passed in cPanel service (cpaneld, whostmgrd, webmaild) and then assembles the URI with the SSL port for
   that service.

=head3 Arguments

   service_name - the name of the cPanel service to get the SSL enabled base URI for. The name can be 'cpaneld',
                  'whostmgrd', or 'webmaild'.

=head3 Returns

   A SSL enabled URI for the passed in service. For example, if you pass in 'cpaneld' and you have an SSL certificate
   for yourdomain.tld installed on cpsrvd, you'd get 'https://yourdomain.tld:2083'.

=cut

sub get_service_ssl_base_uri_by_service_name {
    my ($service_name) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'service_name' ] ) if !length $service_name;

    $ssl_host ||= Cpanel::SSL::Domain::get_best_ssldomain_for_service('cpanel');
    my $port_service_name = $service_name;

    $port_service_name =~ s{d$}{s}g;    # change cpaneld => cpanels
    my $service_port = $Cpanel::Services::Ports::SERVICE{$port_service_name};

    die Cpanel::Exception::create( 'Services::Unknown', [ service => $service_name ] ) if !length $service_port;

    return "https://$ssl_host:$service_port";
}

=head2 clear_cache

=head3 Purpose

   Clear the local cache, mainly used for unit tests.

=head3 Arguments

   none

=head3 Returns

   Always return undef.

=cut

sub clear_cache {
    $ssl_host = undef;
    return;
}

1;
