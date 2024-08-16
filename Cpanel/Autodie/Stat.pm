package Cpanel::Autodie::Stat;

# cpanel - Cpanel/Autodie/Stat.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ( 'stat', 'lstat' );

*stat  = *Cpanel::Autodie::stat;
*lstat = *Cpanel::Autodie::lstat;

1;
