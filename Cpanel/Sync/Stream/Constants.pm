package Cpanel::Sync::Stream::Constants;

# cpanel - Cpanel/Sync/Stream/Constants.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.0';

our $HEADER_SIZE = 16;
our $BUF_SIZE    = 1 << 20;

our $NO_RESPONSE   = 0;
our $WANT_RESPONSE = 1;

1;
