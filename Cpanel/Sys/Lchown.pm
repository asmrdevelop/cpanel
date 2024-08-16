package Cpanel::Sys::Lchown;

# cpanel - Cpanel/Sys/Lchown.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Syscall ();

###########################################################################
#
# Method:
#   lchown
#
# Description:
#   Returns the result from the lchown syscall
#
# Parameters:
#   $path - The path to the symlink to chown
#   $uid  - The uid to set the owner to
#   $gid  - The uid to set the group to
#
# Exceptions:
#   dies on failure from system call
#
# Returns:
#   0 on success
#
# see lchown(2) for more information;
#
sub lchown {
    my ( $path, $uid, $gid ) = @_;

    die "lchown requires a path"        if !defined $path;
    die "lchown requires a numeric UID" if !defined $uid || $uid eq '' || $uid =~ tr/0-9//c;
    die "lchown requires a numeric GID" if !defined $gid || $gid eq '' || $gid =~ tr/0-9//c;

    return Cpanel::Syscall::syscall( 'lchown', $path, int($uid), int($gid) );
}

1;
