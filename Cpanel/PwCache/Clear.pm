package Cpanel::PwCache::Clear;

# cpanel - Cpanel/PwCache/Clear.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache::Cache ();
use Cpanel::NSCD           ();
use Cpanel::SSSD           ();

sub clear_global_cache {
    Cpanel::PwCache::Cache::clear();

    if ( $INC{'Cpanel/PwCache/Build.pm'} ) {

        # only call pwclearcache if Build already loaded
        'Cpanel::PwCache::Build'->can('pwclearcache')->();
    }
    Cpanel::NSCD::clear_cache();
    Cpanel::SSSD::clear_cache();

    return;
}

1;
