package Cpanel::Autodie::UpdateNow;

# cpanel - Cpanel/Autodie/UpdateNow.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=pod

This is used by static scripts to preload all autodie classes.
This package should be autogenerated.

=cut

require Cpanel::Autodie;    # PPI USE OK -- force load autodie modules

#----------------------------------------------------------------------
# Please do not load Cpanel::Autodie::CORE::* modules directly in
# production code; the intended way to load functions at compile time
# is documented in Cpanel/Autodie.pm.
#
# It’s done this way here to accommodate limitations of bin/perlpkg.
#
require Cpanel::Autodie::CORE::chmod;                 # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::chmod_if_exists;       # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::close;                 # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::exists;                # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::fcntl;                 # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::link;                  # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::open;                  # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::print;                 # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::print;                 # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::read;                  # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::readlink;              # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::readlink_if_exists;    # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::rename;                # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::seek;                  # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::stat;                  # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::sysread_sigguard;      # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::syswrite_sigguard;     # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::truncate;              # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::unlink_if_exists;      # PPI USE OK -- force load autodie modules
require Cpanel::Autodie::CORE::exists_nofollow;       # PPI USE OK -- force load autodie modules

1;
