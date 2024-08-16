package Cpanel::Autodie::More::Lite;

# cpanel - Cpanel/Autodie/More/Lite.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# Can’t use Cpanel::Autodie’s normal import() mechanism because
# perlpkg doesn’t interact with that very well. So we have to load
# the CORE::* modules directly.
use Cpanel::Autodie                        ();
use Cpanel::Autodie::CORE::exists          ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::exists_nofollow ();    # PPI USE OK - reload so we can map the symbol below

BEGIN {
    *exists          = *Cpanel::Autodie::exists;
    *exists_nofollow = *Cpanel::Autodie::exists_nofollow;
}
1;
