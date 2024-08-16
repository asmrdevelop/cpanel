package Cpanel::Config::ReverseDnsCache;

# cpanel - Cpanel/Config/ReverseDnsCache.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();
use constant CACHE_FILE            => "/var/cpanel/ip_rdns_cache";
use constant PERSISTENT_CACHE_FILE => "/var/cpanel/ip_rdns_cache.json";

=encoding utf-8

=head1 NAME

Cpanel::Config::ReverseDnsCache - Store a cache of Reverse DNS IP to names.

=head1 SYNOPSIS

    use Cpanel::Config::ReverseDnsCache ();

    my $ip_to_reversedns_map =  Cpanel::Config::ReverseDnsCache::get_ip_to_reversedns_map();

=head1 FUNCTIONS

=head2 get_ip_to_reversedns_map()

Returns a hashref of all reverse dns for the local ips on the system.

Example:
 {
    '192.168.1.1' => 'my.hostname.tld',
    ...
 }

The keys are the local ips, and the values are the reverse dns names.

If 1:1 NAT is enabled the public ip can be obtained by passing the key
though Cpanel::NAT::get_public_ip()

=cut

sub get_ip_to_reversedns_map {
    return scalar Cpanel::Config::LoadConfig::loadConfig( CACHE_FILE(), undef, ': ' );
}

1;
