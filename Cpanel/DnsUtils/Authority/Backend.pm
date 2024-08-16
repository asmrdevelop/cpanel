package Cpanel::DnsUtils::Authority::Backend;

# cpanel - Cpanel/DnsUtils/Authority/Backend.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Authority::Backend

=head1 DESCRIPTION

This module contains individually testable pieces of functionality for
L<Cpanel::DnsUtils::Authority> and related modules.

=cut

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $ret_ar = post_get_soa_and_zones_for_domains( \@DOMAINS, \%DOMAIN_ZONE, \%ZONE_TEXT )

A munging layer after fetching the zones from dnsadmin.

@DOMAINS are all of the domains to check, %DOMAIN_ZONE is a hash of
(domain => zonename). %ZONE_TEXT is a hash of (zonename => zonetext).

The return is an arrayref of hashrefs. Each hashref is:

=over

=item * C<domain>

=item * C<zone> (or undef if there is no zone for the domain)

=item * C<soa> - the zone’s SOA record’s serial number, or -1 if the
domain has no zone

=back

=cut

sub post_get_soa_and_zones_for_domains ( $domains_ar, $domain_zone_hr, $zone_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    my %zone_soas;
    my @ret;
    foreach my $domain (@$domains_ar) {

        my $zone = $domain_zone_hr->{$domain};

        if ($zone) {
            $zone_soas{$zone} //= _get_serial_number_from_zone_file( $zone, \$zone_hr->{$zone} );
            push @ret, { 'domain' => $domain, 'zone' => $zone, 'soa' => $zone_soas{$zone} };
        }
        else {
            push @ret, { 'domain' => $domain, 'zone' => undef, 'soa' => -1 };
        }

    }

    return \@ret;
}

sub _get_serial_number_from_zone_file {

    my ( $zone, $zone_text_sr ) = @_;

    local ( $@, $! );
    require Cpanel::ZoneFile;

    my $zf = Cpanel::ZoneFile->new( 'domain' => $zone, 'text' => $zone_text_sr );

    my @soarecords = $zf->find_records( 'name' => $zone . '.', 'type' => 'SOA' );
    return -1 if !@soarecords;

    return $soarecords[0]->{'serial'};
}

1;
