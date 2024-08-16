package Cpanel::Signal::Numbers;

# cpanel - Cpanel/Signal/Numbers.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#For Linux
our %SIGNAL_NUMBER = (
    'HUP'  => 1,
    'KILL' => 9,
    'TERM' => 15,
    'USR1' => 10,
    'USR2' => 12,
    'ALRM' => 14,
    'CHLD' => 17,
);

1;
