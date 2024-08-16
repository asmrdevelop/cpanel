package Cpanel::Proc;

# cpanel - Cpanel/Proc.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Kill ();
*doom = \&Cpanel::Kill::safekill;

1;
