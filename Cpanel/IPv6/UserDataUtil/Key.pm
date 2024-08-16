package Cpanel::IPv6::UserDataUtil::Key;

# cpanel - Cpanel/IPv6/UserDataUtil/Key.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

## PBI 9919: historical note; originally, IPv6 info was stored in userdata in a
##   key named 'IPV6', defying lowercase convention and also placing that info
##   at the top of the file; $ipv6_key was created to facilitate changing to 'ipv6'
##   and also facilitating finding userdata IPv6 info later (as 'git grep ipv6' is
##   not very telling)
our $ipv6_key = 'ipv6';

1;
