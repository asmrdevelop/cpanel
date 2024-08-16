package Cpanel::Reseller::Cache;

# cpanel - Cpanel/Reseller/Cache.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module exists so that AskDnsAdmin can be compiled in where it’s needed
# but left out where it’s not. The desire is to avoid memory bloat but also
# to avoid the runtime hit from lazy-loading.
#
# At a later point it would be ideal to move the %Cpanel::Reseller::* globals
# into their own modules. (TODO)
#----------------------------------------------------------------------

use strict;

use Cpanel::DnsUtils::AskDnsAdmin ();    # mocked by whostmgr/bin/dnsadmin
use Cpanel::Reseller              ();

#Accepts a list of users whose cache values to reset.
#If there are no users given, this resets them all.
sub reset_cache {
    my (@users) = @_;

    if (@users) {
        delete @Cpanel::Reseller::RESELLER_PRIV_CACHE{@users};
        delete @Cpanel::Reseller::RESELLER_EXISTS_CACHE{@users};
    }
    else {
        %Cpanel::Reseller::RESELLER_PRIV_CACHE   = ();
        %Cpanel::Reseller::RESELLER_EXISTS_CACHE = ();
    }

    $Cpanel::Reseller::reseller_cache_fully_loaded = 0;

    if ( $INC{'Cpanel/DIp.pm'} ) {
        Cpanel::DIp::clearcache();
    }
    _reset_cache_for_dnsadmin(@users) unless $Cpanel::Reseller::is_dnsadmin;

    return 1;
}

sub _reset_cache_for_dnsadmin {
    my (@users) = @_;

    return if $>;

    Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin( 'RESET_CACHE', '', '', '', '', join( ',', @users ) );
    return;
}
1;
