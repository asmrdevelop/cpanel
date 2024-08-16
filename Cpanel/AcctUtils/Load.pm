package Cpanel::AcctUtils::Load;

# cpanel - Cpanel/AcctUtils/Load.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::PwCache::Build ();

my $loadaccountcache_initted = 0;

sub loadaccountcache {
    my $force = shift;

    if ( !$force && $loadaccountcache_initted ) { return; }

    Cpanel::PwCache::Build::init_passwdless_pwcache();

    $loadaccountcache_initted = 1;

    return 1;
}

1;
