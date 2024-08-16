package Cpanel::SafetyBits::Chown;

# cpanel - Cpanel/SafetyBits/Chown.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

require 5.004;
use strict;
use Cpanel::Fcntl   ();
use Cpanel::Debug   ();
use Cpanel::PwCache ();
use Cpanel::SV      ();

our $USER_GID = -2;

################################################################
# safe_chown - Operates exactly like perl's chown, only it does
#   NOT chown hard linked files (i.e., files with >1 name),
#   and it will only chown symlinks themselves,
#   NOT the files to which they point.
# Params:
#    UID - User's name or numeric ID
#    GID - Group's name or numeric ID
#       OR: a GID value of $USER_GID uses the user's group.
#    Files- A list of files to chown.
sub safe_chown {
    my ( $uid, $gid, @files ) = @_;
    my $count = 0;

    my ( $in_uid, $in_gid ) = ( $uid, $gid );
    $in_uid = 'undefined id' unless defined $in_uid;
    $in_gid = 'undefined id' unless defined $in_gid;

    if ( $uid !~ m/^(?:\d+|-1)$/a ) {
        if ( defined $gid && $gid =~ m/^-?\d+$/a && $gid == $USER_GID ) {
            ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam($uid) )[ 2, 3 ];
        }
        else {
            $uid = ( Cpanel::PwCache::getpwnam($uid) )[2];
        }
    }
    if ( defined $gid && $gid =~ m/^-?\d+$/a && $gid == $USER_GID ) {    # can be -1 or -2
        $gid = ( Cpanel::PwCache::getpwuid($uid) )[3];
    }
    elsif ( $gid !~ m/^(?:\d+|-1)$/a ) {
        $gid = ( getgrnam($gid) )[2];
    }

    if ( !defined $uid ) { Cpanel::Debug::log_die("safe_chown: Error fetching uid '$in_uid'"); }
    if ( !defined $gid ) { Cpanel::Debug::log_die("safe_chown: Error fetching gid '$in_gid'"); }

    my $sysopen_flags = Cpanel::Fcntl::or_flags(qw( O_RDONLY O_NOFOLLOW O_EXCL ));

    for my $file (@files) {
        Cpanel::SV::untaint($file);

        sysopen( my $fh, $file, $sysopen_flags ) or do {
            Cpanel::Debug::log_warn("Failed to open “$file” for chown(): $!");
            next;
        };

        if ( my $hard_links = ishardlink($fh) ) {
            Cpanel::Debug::log_warn("Refusing to chown() multiply-linked file “$file” ($hard_links)");
            next;
        }

        #NOTE: This isn't supported in vanilla 5.6, but cPanel has patched 5.6
        #to work with this.
        chown( $uid, $gid, $fh ) or do {
            Cpanel::Debug::log_warn("chown($uid, $gid, $file) failed: $!");
        };

        $count++;
    }

    return $count;
}

# provide a friendly helper to call safe_chown with gid=-2
# in order to guess the gid from Cpanel::PwCache::getpwuid
sub safe_chown_guess_gid {
    my $uid = shift;

    return safe_chown( $uid, $USER_GID, @_ );
}

#Technically, every file is a "hard-linked file";
#this just reports whether a given file has >1 hard link (i.e., >1 name).
sub ishardlink {
    my $file    = shift;
    my $linkage = ( UNIVERSAL::isa( $file, 'GLOB' ) ? stat($file) : lstat($file) )[3];
    return unless -e _;
    return if -d _;
    return ( $linkage > 1 ) ? $linkage : 0;
}

1;
