package Whostmgr::Transfers::State;

# cpanel - Whostmgr/Transfers/State.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my $is_transfer = 0;

# Enable the active transfer setting
# This should be enabled before starting a transfer and a transfer only.
sub start_transfer {
    $is_transfer = 1;
    return 1;
}

# An application setting designating that the current process tree is performing a transfer from another system
sub is_transfer {
    return ( $is_transfer eq 1 ) ? 1 : 0;
}

# Disable the active transfer setting
sub end_transfer {
    $is_transfer = 0;
    return 1;
}

1;
