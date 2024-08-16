package Cpanel::Server::Utils;

# cpanel - Cpanel/Server/Utils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# This is intented to be a lightweight check.  A more exact check would be
# to crawl up the parent process chain and check for cpsrvd, however this
# is sufficient for all of our current use cases and the performance hit of
# making this more robust would likely not be worth it unless we need this
# to work when the 'CPANEL' enviorment variable is not carried.
sub is_subprocess_of_cpsrvd {
    return 0 if $INC{'cpanel/cpsrvd.pm'};    # If we ARE cpsrvd we do not want this behavior
                                             # This should only apply to subprocesses
                                             #
    return $ENV{'CPANEL'} ? 1 : 0;
}

1;
