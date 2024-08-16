package Cpanel::DnsUtils::Authority;

# cpanel - Cpanel/DnsUtils/Authority.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::DnsUtils::Authority::Backend ();
use Cpanel::DnsUtils::ResolverSingleton  ();
use Cpanel::DNS::Unbound                 ();

BEGIN {
    *_resolver = *Cpanel::DnsUtils::ResolverSingleton::singleton;
}

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Authority - Utility functions related to DNS authority

=head1 SYNOPSIS

    use Cpanel::DnsUtils::Authority;

    my $has_local_authority = Cpanel::DnsUtils::Authority::has_local_authority( ["domain1.com", "domain2.com" ]);

=head1 DESCRIPTION

This module contains utility functions relating to determining the DNS authority for domains

=head1 FUNCTIONS

=head2 $domain_authority_hr = has_local_authority()

Determines whether or not local changes to the DNS zones will be authoritative

This method uses a cheap check to see if the server can alter DNS for a list of domains by checking
the local zone's serial number from the SOA record against the serial number found in the SOA record
from public DNS.

The best check would be to actually modify the zone and check it but that would be too agressive.

=over 2

=item Input

=over 3

=item C<ARRAYREF>

An C<ARRAYREF> of domains to check.

=back

=item Output

=over 3

=item C<HASHREF>

A C<HASHREF> where the keys are the domains being checked and the values are booleans indicating
whether or not local changes to DNS will be authoritative.

=back

=back

=cut

sub has_local_authority {
    my ($domains) = @_;
    my $get_soa_and_zones_for_domains = get_soa_and_zones_for_domains($domains);
    return zone_soa_matches_dns_for_domains($get_soa_and_zones_for_domains);

}

=head2 zone_soa_matches_dns_for_domains

Compares the provided SOA serial number for domains to the SOA serial number
found in public DNS for that zone file.

=over 2

=item Input

=over 3

=item C<ARRAYREF>

An arrayref of hashrefs with each hashref having the keys:

=over 4

=item C<domain>

The domain being evaluated.

=item C<zone>

The zone the domain is found in

=item C<soa>

The serial number of the zone

=back

=back

=item Output

=over 3

=item C<HASHREF>

Returns a hashref where the keys are:

=over

=item zone

The DNS zone for the SOA record found via DNS lookup

=item local_authority

1 if the provided serial number matched the serial number found in an SOA record via DNS, 0 otherwise

=item nameservers

A list of nameservers for the domain

=item error

If a DNS lookup error occurred, this indicates what the error was

=back

=back

=back

=cut

sub zone_soa_matches_dns_for_domains {
    my ($get_soa_and_zones_for_domains) = @_;
    my ( %can_alter, %dns_soa, %errors );

    my @zones;
    foreach my $hr ( grep { length $_->{'zone'} } @$get_soa_and_zones_for_domains ) {
        push @zones, $hr->{'zone'};
    }

    my $soa_results_ar = _resolver()->recursive_queries( [ map { [ $_ => 'SOA' ] } @zones ] );
    my $soa_for_zone   = {};

    foreach my $result (@$soa_results_ar) {

        my $err;

        if ( $result->{error} ) {
            $err = $result->{error};
        }
        else {
            ( undef, $err ) = Cpanel::DNS::Unbound::analyze_dns_unbound_result_for_error( @{$result}{ 'name', 'qtype', 'result' } );
        }

        if ($err) {
            $errors{ $result->{name} } = {
                zone            => undef,
                local_authority => 0,
                nameservers     => [],
                error           => $err,
            };
        }
        else {
            $soa_for_zone->{ $result->{name} } = $result->{decoded_data};
        }

    }

    my $nameservers_by_domain = _get_nameservers_for_domains_from_dns( keys %$soa_for_zone );

    foreach my $rec (@$get_soa_and_zones_for_domains) {

        my ( $domain, $zone, $soa ) = @{$rec}{qw(domain zone soa)};

        next if $errors{$domain};

        if ( $zone && $errors{$zone} ) {
            $errors{$domain} = {
                zone            => $zone,
                local_authority => 0,
                nameservers     => [],
                error           => $errors{$zone}{error},
            };

            next;
        }

        $zone ||= _get_zone_from_dns($domain);
        if ($zone) {
            $dns_soa{$zone} //= ref $soa_for_zone->{$zone} ? $soa_for_zone->{$zone}->[0] : undef;
        }

        $can_alter{$domain} = {
            zone            => $zone && $dns_soa{$zone} && $soa eq $dns_soa{$zone}{serial} ? _get_zone_from_dns($domain) : $zone,    # If we're not locally authoritative, prefer the zone from DNS
            local_authority => $zone && $dns_soa{$zone} && $soa eq $dns_soa{$zone}{serial} ? 1                           : 0,
            nameservers     => $nameservers_by_domain->{$domain} || [],
            error           => undef,
        };

    }

    return { %can_alter, %errors };
}

=head2 get_soa_and_zones_for_domain

Retrieves the zone name and SOA serial number from local zone files for the
provided domains.

=over 2

=item Input

=over 3

=item C<ARRAYREF>

An arrayref of domains to lookup

=back

=item Output

=over 3

=item C<ARRAYREF>

Returns an arrayref of hashrefs where each hashref has the keys:

=over 4

=item C<domain>

The domain that was queried

=item C<zone>

The zone that the domain was found in

=item C<soa>

The serial number that was found in the zone

=back

=back

=back

=cut

sub get_soa_and_zones_for_domains {
    my ($domains) = @_;

    my ( $zones_for_domains_map, $zones_hr ) = _get_zones_for_domains($domains);

    return Cpanel::DnsUtils::Authority::Backend::post_get_soa_and_zones_for_domains( $domains, $zones_for_domains_map, $zones_hr );
}

sub _local_zone_files_available {
    require Cpanel::Services::Enabled;
    require Cpanel::DnsUtils::Cluster;
    return Cpanel::Services::Enabled::is_enabled('dns') || Cpanel::DnsUtils::Cluster::is_clustering_enabled();
}

sub _get_zones_for_domains {
    my ($domains) = @_;
    require Cpanel::Domain::Zone;
    return Cpanel::Domain::Zone->new()->get_zones_for_domains($domains);
}

sub _get_nameservers_for_domains_from_dns {
    my (@domains) = @_;
    return _resolver()->get_nameservers_for_domains(@domains);
}

sub _get_nameservers_from_dns {
    my ($domain) = @_;
    my @nsrecords = _resolver()->get_nameservers_for_domain($domain);
    return \@nsrecords;
}

sub _get_zone_from_dns {
    my ($domain) = @_;
    return _resolver()->get_zone_for_domain($domain);
}

1;
