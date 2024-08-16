package Cpanel::Domain::Local;

# cpanel - Cpanel/Domain/Local.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Socket::Micro  ();
use Cpanel::IP::LocalCheck ();
use Cpanel::IP::Loopback   ();
use Cpanel::Validate::IP   ();

#for testing
*Cpanel::Domain::Local::_inet_ntoa = *Cpanel::Socket::Micro::inet_ntoa;
#

my %_iaddr_cache;

# https://en.wikipedia.org/wiki/Uniform_resource_locator
# scheme://[user:password@]domain:port/path?query_string#fragment_id
# domain name or literal numeric IP address
sub domain_or_ip_is_on_local_server {
    my ($domain_or_ip) = @_;

    return 1 if Cpanel::IP::Loopback::is_loopback($domain_or_ip);
    if ( Cpanel::Validate::IP::is_valid_ip($domain_or_ip) ) {
        return Cpanel::IP::LocalCheck::ip_is_on_local_server($domain_or_ip);
    }
    elsif ( $_iaddr_cache{$domain_or_ip} //= gethostbyname($domain_or_ip) ) {
        return Cpanel::IP::LocalCheck::ip_is_on_local_server( _inet_ntoa( $_iaddr_cache{$domain_or_ip} ) );
    }
    return 0;
}

1;
