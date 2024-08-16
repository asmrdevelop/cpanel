package Cpanel::API::Domain;

# cpanel - Cpanel/API/Domain.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module is for things that concern *domains*
# It is NOT for Apache vhosts, which is how cPanel traditionally has regarded
# the concept of “domain”.
#
# If what you want has anything to do with web, such as:
#   - ServerName or ServerAlias
#   - document root
#   - virtual hosts
#   - web sites or HTTP
#
# … then check a module like Cpanel::WebVhosts.
#----------------------------------------------------------------------

use strict;
use warnings;

1;
