package Cpanel::Output::Pkgacct;

# cpanel - Cpanel/Output/Pkgacct.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use parent qw( Cpanel::Output::Formatted::TimeStamp Cpanel::Output::Formatted::Terminal );

#NOTE: warn() etc. will not prefix entries with the timestamp “out of the box”
#with this module; you have to pass in the flag that signifies that that
#should happen.

1;

__END__
