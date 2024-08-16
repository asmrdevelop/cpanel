package Cpanel::ExceptionMessage;

# cpanel - Cpanel/ExceptionMessage.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Exception ();

*load_perl_module = \&Cpanel::Exception::load_perl_module;

1;
