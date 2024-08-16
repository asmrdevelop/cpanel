package Cpanel::Mount;

# cpanel - Cpanel/Mount.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $MNT_FORCE  = 1;
our $MNT_DETACH = 2;

sub umount {
    my ( $path, $flags ) = @_;

    $flags |= 0;

    return syscall( 166, $path, $flags );    # __NR_umount2
}

1;
