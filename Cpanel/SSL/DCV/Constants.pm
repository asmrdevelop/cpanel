package Cpanel::SSL::DCV::Constants;

# cpanel - Cpanel/SSL/DCV/Constants.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant {
    REQUEST_URI_DCV_PATH           => '^/\\.well-known/cpanel-dcv/[0-9a-zA-Z_-]+$',
    URI_DCV_ALLOWED_CHARACTERS     => [ 0 .. 9, 'A' .. 'Z', '_', '-' ],
    URI_DCV_RANDOM_CHARACTER_COUNT => 32,
    URI_DCV_RELATIVE_PATH          => '.well-known/cpanel-dcv',
    EXTENSION                      => '',
};

1;
