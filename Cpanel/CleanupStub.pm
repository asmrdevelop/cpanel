package Cpanel::CleanupStub;

# cpanel - Cpanel/CleanupStub.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::CloseFDs ();

use strict;
use warnings;

our $VERSION = '2.0';

*closefds       = *Cpanel::CloseFDs::fast_closefds;
*daemonclosefds = *Cpanel::CloseFDs::fast_daemonclosefds;

1;
