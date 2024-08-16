package Cpanel::Autodie::Read;

# cpanel - Cpanel/Autodie/Read.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ('read');

*read = *Cpanel::Autodie::read;

1;
