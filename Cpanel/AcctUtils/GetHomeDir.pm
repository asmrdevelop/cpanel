package Cpanel::AcctUtils::GetHomeDir;

# cpanel - Cpanel/AcctUtils/GetHomeDir.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache ();

*gethomedir = *Cpanel::PwCache::gethomedir;

1;
