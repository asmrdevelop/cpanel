package Cpanel::Hostname;

# cpanel - Cpanel/Hostname.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Sys::Hostname ();

our $VERSION = 2.0;

{
    no warnings 'once';
    *gethostname   = *Cpanel::Sys::Hostname::gethostname;
    *shorthostname = *Cpanel::Sys::Hostname::shorthostname;
}

1;
