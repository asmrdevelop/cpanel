package Cpanel::Lchown;

# cpanel - Cpanel/Lchown.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Sys::Lchown ();

# No Try::Tiny for memory

###########################################################################
#
# Method:
#   lchown
#
# Description:
#   Changes the ownership of a set of symlinks
#
# Parameters:
#   $uid   - The uid to set the owner to
#   $gid   - The uid to set the group to
#   @files - The symlinks to set the onwership for
#
# Returns:
#		0 - Failed to set Lchown
#		1 - Lchown set
#
# Note: this interface is designed to replace Lchown::lchown
# and cannot be changed
#
sub lchown {
    my ( $uid, $gid, @files ) = @_;

    local $@;
    my $changed = 0;
    foreach my $file (@files) {
        my $result = eval { Cpanel::Sys::Lchown::lchown( $file, $uid, $gid ) };
        if ( !$@ ) {
            $changed++ if $result == 0;
        }
    }
    return $changed;
}
1;
