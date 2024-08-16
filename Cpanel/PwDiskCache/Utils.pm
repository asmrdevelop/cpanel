package Cpanel::PwDiskCache::Utils;

# cpanel - Cpanel/PwDiskCache/Utils.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Autodie            ();
use Cpanel::Validate::Username ();

#FIXME: Duplicated in Cpanel::PwDiskCache. Everything should go through this
#module, though, for the actual filesystem mechanics; the tie()d module will
#then be just a functionality shim around this backend.
#
#NOTE: Exposed globally for tests only.
our $_cache_dir = '/var/cpanel/pw.cache';

#This returns the number of filesystem nodes unlink()ed.
#It throws an appropriate exception on error.
#
#NOTE: This overwrites global $! and $^E.
#
sub remove_entry_for_user {
    my ($username) = @_;

    Cpanel::Validate::Username::validate_or_die($username);

    #There are two links to the same file.

    my $uid = ( getpwnam $username )[2];

    my $inode;

    my $unlinked = 0;

    if ( _entry_exists("0:$username") ) {
        $inode = ( stat _ )[1];

        $unlinked += _remove_entry("0:$username");
    }

    if ( defined $uid ) {
        $unlinked += _remove_entry_if_exists("2:$uid");
    }
    elsif ($inode) {
        Cpanel::Autodie::opendir( my $dh, $_cache_dir );

        for my $node ( readdir $dh ) {
            next if substr( $node, 0, 1 ) ne '2:';
            if ( ( stat "$_cache_dir/$node" )[1] == $inode ) {
                $unlinked += Cpanel::Autodie::unlink("$_cache_dir/$node");
            }
        }

        Cpanel::Autodie::closedir($dh);
    }

    return $unlinked;
}

sub _remove_entry_if_exists {
    my ($key) = @_;

    return _entry_exists($key) ? _remove_entry($key) : 0;
}

sub _entry_exists {
    my ($key) = @_;

    return -e "$_cache_dir/$key";
}

sub _remove_entry {
    my ($key) = @_;

    return Cpanel::Autodie::unlink("$_cache_dir/$key");
}

1;
