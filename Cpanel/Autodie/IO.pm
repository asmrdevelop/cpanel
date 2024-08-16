package Cpanel::Autodie::IO;

# cpanel - Cpanel/Autodie/IO.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# Can’t use Cpanel::Autodie’s normal import() mechanism because
# perlpkg doesn’t interact with that very well. So we have to load
# the CORE::* modules directly.
use Cpanel::Autodie                 ();
use Cpanel::Autodie::CORE::print    ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::close    ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::seek     ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::truncate ();    # PPI USE OK - reload so we can map the symbol below

*print    = *Cpanel::Autodie::print;
*close    = *Cpanel::Autodie::close;
*seek     = *Cpanel::Autodie::seek;
*truncate = *Cpanel::Autodie::truncate;

1;
