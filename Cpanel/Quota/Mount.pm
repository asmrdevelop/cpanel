package Cpanel::Quota::Mount;

# cpanel - Cpanel/Quota/Mount.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Filesys::Mounts ();

sub getmnt {
    my ($device) = @_;
    if ( $device ne '/dev/mysql' && $device ne '/dev/postgres' ) {
        $device = Cpanel::Filesys::Mounts::get_mount_point_from_device($device);
        $device = '/' if !$device || $device eq '/dev/root';
    }
    return $device;
}

1;
