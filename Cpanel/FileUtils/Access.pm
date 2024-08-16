package Cpanel::FileUtils::Access;

# cpanel - Cpanel/FileUtils/Access.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AccessIds::Normalize ();
use Cpanel::Exception            ();
use Cpanel::FHUtils::Tiny        ();

#Four args:
#   - path OR filehandle
#   - mode
#   - user or uid
#   - group or gid (optional; defaults to user's group/GID)
#
sub ensure_mode_and_owner {
    my ( $path_or_fh, $mode, $user_or_uid, $group_or_gid ) = @_;

    die "Must be at least three args!" if !length $path_or_fh || !length $mode || !length $user_or_uid;

    if ( $mode =~ tr{0-9}{}c || $mode > 07777 ) {
        die "Invalid mode: “$mode”";
    }

    my ( $uid, $gid );
    if ( length $user_or_uid && $user_or_uid !~ tr{0-9}{}c && length $group_or_gid && $group_or_gid !~ tr{0-9}{}c ) {
        $uid = $user_or_uid;
        $gid = $group_or_gid;
    }
    else {
        ( $uid, $gid ) = Cpanel::AccessIds::Normalize::normalize_user_and_groups(
            $user_or_uid,
            length($group_or_gid) ? $group_or_gid : (),
        );

        die "Invalid user/UID: “$user_or_uid”"   if !length $uid;
        die "Invalid group/GID: “$group_or_gid”" if !length $gid;
    }

    local ( $!, $^E );

    my ( $cur_mode, $cur_uid, $cur_gid ) = ( stat $path_or_fh )[ 2, 4, 5 ] or do {
        die "Invalid path or filehandle: “$path_or_fh”";
    };

    my $needs_chmod = ( ( $cur_mode & 07777 ) != $mode );
    my $needs_chown = ( ( $cur_uid != $uid ) || ( $cur_gid != $gid ) );

    return 1 unless ( $needs_chmod || $needs_chown );

    #Always operate on a file handle so we are confident that both ops
    #are working on the same actual file.
    my $fh;
    if ( Cpanel::FHUtils::Tiny::is_a($path_or_fh) ) {
        $fh = $path_or_fh;
    }
    else {
        #This does work on directories.
        open $fh, '<:stdio', $path_or_fh or do {
            if ( -d $path_or_fh ) {
                die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $path_or_fh, error => $! ] );
            }

            die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $path_or_fh, mode => '<', error => $! ] );
        };
    }

    if ($needs_chmod) {
        chmod( $mode, $fh ) or die Cpanel::Exception::create( 'IO::ChmodError', [ path => $path_or_fh, permissions => $mode, error => $! ] );
    }

    if ($needs_chown) {
        chown( $uid, $gid, $fh ) or die Cpanel::Exception::create( 'IO::ChownError', [ path => $path_or_fh, uid => $uid, gid => $gid, error => $! ] );
    }

    return 1;
}

1;
