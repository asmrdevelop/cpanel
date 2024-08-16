package Cpanel::Chkservd::Tiny::Suspended;

# cpanel - Cpanel/Chkservd/Tiny/Suspended.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
#  Do not modify this file as it will bloat tailwatchd
#

our $suspend_file = '/var/run/chkservd.suspend';

sub is_suspended {
    return -e $suspend_file ? 1 : 0;
}

1;
