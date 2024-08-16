package Cpanel::CSS;

# cpanel - Cpanel/CSS.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# $1 and $3 are before/after the URL itself; $2 is the URL.
our $CSS_URL_REGEXP = q!(url\()["'\s]*([^\s'"\)](?:[^\)"']*[^\s'"\)])?)["'\s]*(\))!;

1;
