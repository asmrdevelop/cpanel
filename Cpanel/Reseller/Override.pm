package Cpanel::Reseller::Override;

# cpanel - Cpanel/Reseller/Override.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This has been handled in the past by directly checking the CPRESELLER
# environment variable, which may not be the safest solution.  By placing this
# in functions, we can change the implementation later to something potentially
# safer.

use strict;

sub is_overriding {
    return ( length( $ENV{'CPRESELLER'} ) && length($Cpanel::user) && ( $ENV{'CPRESELLER'} ne $Cpanel::user ) ) ? 1 : 0;
}

sub is_overriding_from {
    return $ENV{'CPRESELLER'};
}

1;
