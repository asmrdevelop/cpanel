package Cpanel::Autodie::Perms;

# cpanel - Cpanel/Autodie/Perms.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ( 'chmod', 'chown' );

*chmod = *Cpanel::Autodie::chmod;
*chown = *Cpanel::Autodie::chown;

1;
