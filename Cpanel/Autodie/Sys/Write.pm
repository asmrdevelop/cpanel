package Cpanel::Autodie::Sys::Write;

# cpanel - Cpanel/Autodie/Sys/Write.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module contains convenience-replacements for Perl built-ins.
# Its calls wrap Cpanel::Autodie to reap the benefits of that module.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Autodie ('syswrite');

*syswrite = \*Cpanel::Autodie::syswrite;

1;
