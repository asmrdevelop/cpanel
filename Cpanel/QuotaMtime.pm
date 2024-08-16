package Cpanel::QuotaMtime;

# cpanel - Cpanel/QuotaMtime.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#

use Try::Tiny;

use Cpanel::LoadFile ();

my %MOUNT_POINTS;
my $mount_points_mtime;

our $FSTAB_FILE = '/etc/fstab';

# get_quota_mtime
# returns the mtime of the last written system quota database
#
sub get_quota_mtime {
    my ($mtime_to_beat) = @_;
    my $maxmtime = 0;

    my $fstab_mtime = ( stat($FSTAB_FILE) )[9];

    # Some Virtuozzo systems don't have /etc/fstab.
    return 0 unless defined $fstab_mtime;

    my $mount_points_ref;

    if ( !$mount_points_mtime || $mount_points_mtime != $fstab_mtime ) {
        $mount_points_mtime = $fstab_mtime;
        $mount_points_ref   = _get_mount_points_with_quota();
    }

    foreach my $quota_file ( map { $_ . '/aquota.user', $_ . '/quota.user' } @$mount_points_ref ) {
        my $qmtime = ( stat($quota_file) )[9] or next;
        return $qmtime if ( $mtime_to_beat && $qmtime > $mtime_to_beat );
        if ( $qmtime > $maxmtime ) { $maxmtime = $qmtime; }
    }

    return $maxmtime;
}

sub _get_mount_points_with_quota {
    my %MOUNT_POINTS   = ();
    my $fstab_contents = try { Cpanel::LoadFile::load($FSTAB_FILE); };
    return [] if !defined $fstab_contents;
    my ( $dev, $mntpoint, $fstype, $options );
    foreach my $line ( grep { index( $_, 'quota' ) > -1 && ( index( $_, '#' ) == -1 || !m{^[ \t]*\#} ) } split( m{\n}, $fstab_contents ) ) {

        # parse each mount point and retrieve the newest mtime
        # from quota.user and aquota.user files.
        if ( ( ( $dev, $mntpoint, $fstype, $options ) = split( m{[ \t]+}, $line ) )[0] ) {
            if (
                   !length $mntpoint
                || !length $fstype
                || ( $options && index( $options, 'quota' ) == -1 )
                ||                                                                                                                                                           # do not check fses without quota
                ( index( $mntpoint, '/virtfs/' ) != -1 || $mntpoint eq 'swap' || index( $mntpoint, '/' ) != 0 || $mntpoint =~ m/^\/(?:mnt\/|swap|proc|dev|boot|sys)/ ) ||    #why waste a stat() ?
                ( $fstype eq 'nfs' || $fstype eq 'coda' || $fstype eq 'smb' )                                                                                                #do not check network filesystems as they may be slow
            ) {
                next;
            }
            $mntpoint =~ s/\/+$//;
            $MOUNT_POINTS{$mntpoint} = undef;
        }
    }
    return [ keys %MOUNT_POINTS ];
}

1;
