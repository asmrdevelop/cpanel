
# cpanel - Cpanel/Horde/Tmpdir.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DAV::Tmpdir;

use strict;
use warnings;
use Cpanel::PwCache ();

# Assumption of this module: It must already be running as the user in question.

# Returns the desired value for TMPDIR for the DAV application.
# Ensures that the path exists.
sub for_current_user {
    my $home     = Cpanel::PwCache::gethomedir() || die("Could not detect home directory\n");
    my $tmp_rel  = '/tmp/dav';
    my $tmp_full = $home . $tmp_rel;

    if ( $> == 0 || $< == 0 ) {
        require Carp;
        Carp::confess('This function should not be run as root');
    }

    # Create the tmp dir if it doesn't exist
    if ( !-e $tmp_full ) {
        my $check_path = $home;
        foreach my $segment ( split '/', $tmp_rel ) {
            $check_path .= "$segment/";
            mkdir( $check_path, 0700 ) if !-e $check_path;
        }
    }

    return $tmp_full;
}

1;
