package Cpanel::OSSys::Bits;

# cpanel - Cpanel/OSSys/Bits.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $MAX_32_BIT_SIGNED;
our $MAX_32_BIT_UNSIGNED;
our $MAX_64_BIT_SIGNED;
our $MAX_64_BIT_UNSIGNED;

our $MAX_NATIVE_SIGNED;
our $MAX_NATIVE_UNSIGNED;

sub getbits {
    return length( pack( 'l!', 1000 ) ) * 8;
}

BEGIN {
    $MAX_32_BIT_UNSIGNED = ( 1 << 32 ) - 1;
    $MAX_32_BIT_SIGNED   = ( 1 << 31 ) - 1;

    $MAX_64_BIT_UNSIGNED = ~0;         #true on both 32- and 64-bit systems
    $MAX_64_BIT_SIGNED   = -1 >> 1;    #true on both 32- and 64-bit systems

    if ( getbits() == 32 ) {
        $MAX_NATIVE_SIGNED   = $MAX_32_BIT_SIGNED;
        $MAX_NATIVE_UNSIGNED = $MAX_32_BIT_UNSIGNED;
    }
    else {
        $MAX_NATIVE_SIGNED   = $MAX_64_BIT_SIGNED;
        $MAX_NATIVE_UNSIGNED = $MAX_64_BIT_UNSIGNED;
    }
}

1;
