package Cpanel::WebVhosts::Aliases;

# cpanel - Cpanel/WebVhosts/Aliases.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::userdata::Load ();
use Cpanel::Context                ();
use Cpanel::WebVhosts::AutoDomains ();

#Meant to be called from a cpanel.pl process.
#Note that this does NOT include the service (formerly proxy) subdomains that we now add to
#SSL vhosts!
sub get_builtin_alias_subdomains {
    my ( $domain, $vh_servername ) = @_;

    Cpanel::Context::must_be_list();

    #This is cached in memory so shouldn’t be a significant
    #slowdown for multiple reads for the same vhost.
    my $ud = Cpanel::Config::userdata::Load::load_userdata_domain_or_die(
        ( $Cpanel::user || die 'Must have $Cpanel::user set!' ),
        $vh_servername,
    );

    my @labels = (
        Cpanel::WebVhosts::AutoDomains::ON_ALL_CREATED_DOMAINS(),
        Cpanel::WebVhosts::AutoDomains::WEB_SUBDOMAINS_FOR_ZONE(),
    );

    my @web_aliases;
    for my $prefix (@labels) {
        if ( $ud->{'serveralias'} =~ m<(?:\A|\s) \Q$prefix\E\.\Q$domain\E (?:\z|\s)>x ) {
            push @web_aliases, $prefix;
        }
    }

    return @web_aliases;
}

1;
