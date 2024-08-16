package Cpanel::UserZones;

# cpanel - Cpanel/UserZones.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module has nothing to do with “users”; it’s just a mass-grab
# of every possible zone that could have entries for the given domains.
#----------------------------------------------------------------------

use strict;
use warnings;
use Cpanel::DnsUtils::Fetch ();

sub get_all_user_zones {
    my @DOMAINS = @_;
    my %possible_zone_list;
    foreach my $dns (@DOMAINS) {
        $possible_zone_list{$dns} = 1;
        my @sep_dns = split( /\./, $dns );
        while ( shift(@sep_dns) && $#sep_dns > 0 ) {    #must have two parts (do not check .com)
            $possible_zone_list{ join( '.', @sep_dns ) } = 1;
        }
    }

    my $zone_ref = Cpanel::DnsUtils::Fetch::fetch_zones( 'zones' => [ keys %possible_zone_list ] );
    foreach my $dns ( keys %possible_zone_list ) {
        $zone_ref->{$dns} ||= [];
    }
    foreach my $dns ( keys %$zone_ref ) {
        if ( !ref $zone_ref->{$dns} ) {
            $zone_ref->{$dns} = [ split( m{\n}, $zone_ref->{$dns} ) ];
        }
    }
    return $zone_ref;
}

1;
