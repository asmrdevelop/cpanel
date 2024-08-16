package Cpanel::Config::ReverseDnsCache::Update;

# cpanel - Cpanel/Config/ReverseDnsCache/Update.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use AnyEvent     ();
use Promise::ES6 ();

use Cpanel::Exception               ();
use Cpanel::NAT                     ();
use Cpanel::IP::Local               ();
use Cpanel::DNS::Unbound::Async     ();
use Cpanel::DnsUtils::ReverseDns    ();
use Cpanel::Config::FlushConfig     ();
use Cpanel::Config::ReverseDnsCache ();
use Cpanel::Transaction::File::JSON ();

=encoding utf-8

=head1 NAME

Cpanel::Config::ReverseDnsCache::Update - Update the cache of Reverse DNS IP to names.

=head1 SYNOPSIS

    use Cpanel::Config::ReverseDnsCache::Update;

    Cpanel::Config::ReverseDnsCache::Update::update_reverse_dns_cache();

=head1 FUNCTIONS

=head2 update_reverse_dns_cache()

This function queries DNS to update the map of local ip to reverse dns
name that is returned by Cpanel::Config::ReverseDnsCache::get_ip_to_reversedns_map()

For additional details please see the documentation for
Cpanel::Config::ReverseDnsCache::get_ip_to_reversedns_map()

This function returns 1 on success and throws and execption on failure.

=cut

sub update_reverse_dns_cache {

    my %local_ip_name;

    my @public_ips             = Cpanel::IP::Local::get_local_systems_public_ips();
    my %public_to_local_ip_map = map { $_ => Cpanel::NAT::get_local_ip($_) } @public_ips;

    my $ub = Cpanel::DNS::Unbound::Async->new();

    my @promises;

    foreach my $ip (@public_ips) {
        push @promises, Cpanel::DnsUtils::ReverseDns::promise_ptrs_for_ip( $ub, $ip )->then(
            sub ($ptrs_ar) {
                if ( my $name = $ptrs_ar->[0] ) {
                    $local_ip_name{ $public_to_local_ip_map{$ip} } = $name;
                }
            },
            sub ($error) {
                warn Cpanel::Exception::get_string($error);
            },
        );
    }

    AnyEvent->now_update();
    my $cv = AnyEvent->condvar();
    Promise::ES6->all( \@promises )->then($cv);

    $cv->recv();

    my %local_to_public_ip_map = reverse %public_to_local_ip_map;
    my $ip_to_ptr_map_hr       = _merge_ip_reverse_map_and_update_persistent_cache( \%local_ip_name, \%local_to_public_ip_map );

    _write_ip_to_ptr_cache_file($ip_to_ptr_map_hr);

    return 1;
}

sub _merge_ip_reverse_map_and_update_persistent_cache ( $local_ip_name_hr, $local_to_public_ip_map_hr ) {    ## no critic qw(ProhibitManyArgs)

    # Load the persistent cache. We keep the results of previous runs on disk so
    # any failure or missing PTR records do not make the system suddenly switch
    # what is in the cache file which could result in an unexpected change in outgoing
    # EHLO/HELO.
    my $transaction = Cpanel::Transaction::File::JSON->new( path => Cpanel::Config::ReverseDnsCache::PERSISTENT_CACHE_FILE(), "permissions" => 0644 );
    my $data        = $transaction->get_data();
    $data = {} if !$data || ref $data ne 'HASH';
    my $ip_to_ptr_map_hr = ( $data->{'ip_to_ptr_map'} ||= {} );

    # We merge all the successful lookup results into the cache
    @{$ip_to_ptr_map_hr}{ keys %$local_ip_name_hr } = values %$local_ip_name_hr;

    # We remove all the unknown local ips in the cache so that
    # if the system changes ip addresses we do not carry around cruft
    # in the cache
    delete @{$ip_to_ptr_map_hr}{ grep { !$local_to_public_ip_map_hr->{$_} } keys %$ip_to_ptr_map_hr };

    # Finally write everything to disk so the cache persists
    $transaction->set_data($data);
    $transaction->save_and_close_or_die();

    # Return the result so we can use it for the exim friendly
    # file
    return $ip_to_ptr_map_hr;
}

sub _write_ip_to_ptr_cache_file ($ip_to_ptr_map_hr) {

    Cpanel::Config::FlushConfig::flushConfig(
        Cpanel::Config::ReverseDnsCache::CACHE_FILE(),
        $ip_to_ptr_map_hr,
        ': ',
    );

    return 1;
}
1;
