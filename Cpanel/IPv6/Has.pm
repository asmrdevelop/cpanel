package Cpanel::IPv6::Has;

# cpanel - Cpanel/IPv6/Has.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $ipv6_test_file = '/proc/net/if_inet6';
#
# Test if the system has support for IPv6
#
sub system_has_ipv6 {

    # If it doesnt exist, we don't have it
    return 0 unless ( -f $ipv6_test_file );

    # We should be able to open if it has it
    open my $fh, '<', $ipv6_test_file or return 0;

    # Try to read a line from the file
    my $line = <$fh>;
    close $fh;

    # Return true false based on if we read something
    return $line ? 1 : 0;
}

1;
