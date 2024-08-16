package Cpanel::Template::Plugin::Geo;

# cpanel - Cpanel/Template/Plugin/Geo.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent 'Template::Plugin';

use Try::Tiny;

use Cpanel::CountryCodes ();
use Cpanel::LoadModule   ();

*COUNTRY_CODES = \&Cpanel::CountryCodes::COUNTRY_CODES;

#This defaults to the REMOTE_HOST’s country code.
#If there is none (e.g., because REMOTE_HOST is a private IP address),
#then try the server’s main IP address.
#If that doesn’t work, fall back to Cpanel::NAT::get_public_ip().
sub guess_country_code {
    my $ip = $ENV{'REMOTE_HOST'} or die 'No REMOTE_HOST env!';

    my $ccode;

    try {
        Cpanel::LoadModule::load_perl_module('Cpanel::GeoIPfree');

        #We don’t care about the country name.
        ($ccode) = Cpanel::GeoIPfree->new()->LookUp($ip);

        #We could use the stored server main IP for this,
        #but that only works in production. OpenDNS::MyIP will work
        #in development/testing environments as well.
        if ( $ccode eq 'ZZ' ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::IP::Public');
            ($ccode) = Cpanel::GeoIPfree->new()->LookUp( Cpanel::IP::Public::get_public_ipv4() );
        }
    }
    catch {
        warn "Failed to guess a country code (remote IP “$ENV{'REMOTE_HOST'}”): $_";
    };

    # In the case of IPV6 REMOTE_HOSTS, GeoIP sometimes doesn't return anything.
    # This ensures a default in that instance.
    return $ccode || "US";
}

1;
