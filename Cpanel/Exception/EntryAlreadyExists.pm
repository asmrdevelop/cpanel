package Cpanel::Exception::EntryAlreadyExists;

# cpanel - Cpanel/Exception/EntryAlreadyExists.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This exception class describes a condition of “that thing already
# exists”. It’s a generic error that can be instantiated directly or
# subclassed.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::Exception );

1;
