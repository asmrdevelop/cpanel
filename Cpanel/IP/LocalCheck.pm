package Cpanel::IP::LocalCheck;

# cpanel - Cpanel/IP/LocalCheck.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::IP::Bound    ();
use Cpanel::IP::Loopback ();
use Cpanel::NAT          ();
use Cpanel::LoadModule   ();

sub ip_is_on_local_server {
    my ($ip) = @_;

    die "ip_is_on_local_server() requires an ip address" if !$ip;

    return 1 if Cpanel::IP::Loopback::is_loopback($ip);

    #TODO: Investigate whether we can “check” these directly
    #rather than harvesting all of the IP addresses...
    if ( $ip =~ tr{:}{} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::IP::Local')  unless $INC{'Cpanel/IP/Local.pm'};
        Cpanel::LoadModule::load_perl_module('Cpanel::IP::Expand') unless $INC{'Cpanel/IP/Expand.pm'};
        my $expanded_ip = Cpanel::IP::Expand::expand_ip( $ip, 6 );

        # TODO: get_local_systems_public_ipv6_ips does not cache IPv6s
        # A few versions ago we converted it to use netlink so its much faster,
        # however we should add caching at some point in the future when
        # IPv6 becomes more prevalent.
        foreach my $unexpanded_ipv6 ( Cpanel::IP::Local::get_local_systems_public_ipv6_ips() ) {
            return 1 if $unexpanded_ipv6 eq $expanded_ip;
            return 1 if Cpanel::IP::Expand::expand_ip( $unexpanded_ipv6, 6 ) eq $expanded_ip;
        }
    }
    else {
        return 1 if Cpanel::IP::Bound::ipv4_is_bound($ip);
        my $local_ip = Cpanel::NAT::get_local_ip($ip);
        if ( $local_ip ne $ip ) {
            return 1 if Cpanel::IP::Bound::ipv4_is_bound($local_ip);
        }
    }

    return 0;
}

1;
