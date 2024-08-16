package Cpanel::Autodie::Unlink::Lite;

# cpanel - Cpanel/Autodie/Unlink/Lite.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ('unlink');

*unlink = \*Cpanel::Autodie::unlink;

1;
