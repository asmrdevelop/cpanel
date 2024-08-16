package Cpanel::Autodie::Readlink;

# cpanel - Cpanel/Autodie/Readlink.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Use this module for error-checked I/O in Perl.
#
# This confers many of autodie.pm's benefits without actually overwriting
# Perl built-ins as that module does.
#
# See Cpanel::Autodie for more information.

use strict;
use warnings;

use Cpanel::Autodie ( 'readlink', 'readlink_if_exists' );

*readlink           = *Cpanel::Autodie::readlink;
*readlink_if_exists = *Cpanel::Autodie::readlink_if_exists;

1;
