package Cpanel::Autodie::Dir;

# cpanel - Cpanel/Autodie/Dir.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module is not really meant for public consumption beyond the
# Cpanel::Autodie:: namespace.
#----------------------------------------------------------------------

use strict;
use warnings;

# Can’t use Cpanel::Autodie’s normal import() mechanism because
# perlpkg doesn’t interact with that very well. So we have to load
# the CORE::* modules directly.
use Cpanel::Autodie                        ();
use Cpanel::Autodie::CORE::opendir         ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::rewinddir       ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::closedir        ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::mkdir           ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::rmdir           ();    # PPI USE OK - reload so we can map the symbol below
use Cpanel::Autodie::CORE::rmdir_if_exists ();    # PPI USE OK - reload so we can map the symbol below

*opendir         = *Cpanel::Autodie::opendir;
*rewinddir       = *Cpanel::Autodie::rewinddir;
*closedir        = *Cpanel::Autodie::closedir;
*mkdir           = *Cpanel::Autodie::mkdir;
*rmdir           = *Cpanel::Autodie::rmdir;
*rmdir_if_exists = *Cpanel::Autodie::rmdir_if_exists;

1;
