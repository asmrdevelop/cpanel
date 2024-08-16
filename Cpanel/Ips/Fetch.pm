package Cpanel::Ips::Fetch;

# cpanel - Cpanel/Ips/Fetch.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::IP::Configured ();

#
# FIXME: Cpanel::IP::Configured::getconfiguredips does the same thing
# but with cache
#
sub fetchipslist {
    my $ip_ref      = Cpanel::IP::Configured::getconfiguredips();
    my $ips_hashref = { map { $_ => 1 } @{$ip_ref} };
    return wantarray ? %{$ips_hashref} : $ips_hashref;
}

#copy of the above, but it actually gives a "list" ;-)
sub fetch_ips_array {
    my $ip_ref = Cpanel::IP::Configured::getconfiguredips();
    return wantarray ? @{$ip_ref} : $ip_ref;
}

1;
