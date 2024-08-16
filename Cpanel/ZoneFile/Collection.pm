package Cpanel::ZoneFile::Collection;

# cpanel - Cpanel/ZoneFile/Collection.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ZoneFile::Edit ();

=encoding utf-8

=head1 NAME

Cpanel::ZoneFile::Collection - Create collections of Cpanel::ZoneFile::Edit objects

=head1 SYNOPSIS
    use Cpanel::Domain::Zone ();
    use Cpanel::DnsUtils::Fetch ();
    use Cpanel::ZoneFile::Collection ();

    # If you have a list of domains
    my ( $domain_to_zone_map_hr, $zones_hr ) = Cpanel::Domain::Zone->new()->get_zones_for_domains( \@domains );

    # If you have a list of zones
    my $zone_hr = Cpanel::DnsUtils::Fetch::fetch_zones( 'zones' => \@zones );

    my $zone_file_objs_hr = Cpanel::ZoneFile::Collection::create_zone_file_objs($zone_hr);

=head2 create_zone_file_objs($zones_hr)

This function takes a hashref of zones ($zonename => $zone_text, à la
C<Cpanel::DnsUtils::Fetch::fetch_zones()>) and
returns a hashref of L<Cpanel::ZoneFile::Edit> instances, keyed
on the zone name.

=cut

sub create_zone_file_objs {
    my ($zones_hr) = @_;

    my %zone_file_objs;

    #Avoid potential bugs in code that mishandles $@.
    local $@;

    foreach my $zonename ( keys %$zones_hr ) {
        my $zonefile_obj;
        my $ok = eval { $zonefile_obj = Cpanel::ZoneFile::Edit->new( 'domain' => $zonename, 'text' => $zones_hr->{$zonename} ); 1 };

        my $err = $ok ? $zonefile_obj->{'error'} : $@;

        if ($err) {
            warn(qq{The zone "$zonename" could not be parsed because of an error: $err});
        }
        else {
            $zone_file_objs{$zonename} = $zonefile_obj;
        }
    }

    return \%zone_file_objs;
}

1;
