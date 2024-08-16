package Cpanel::Exception::ContextError;

# cpanel - Cpanel/Exception/ContextError.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

#----------------------------------------------------------------------
#NOTE: Since context errors are for internal consumption only,
#we do NOT translate them.
#----------------------------------------------------------------------

1;
