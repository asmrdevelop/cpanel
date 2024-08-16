package Cpanel::Filesys::Mount;

# cpanel - Cpanel/Filesys/Mount.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Filesys::Mount

=cut

use strict;
use warnings;

# use the mounted partitions and not the one listed in fstab
our $mtab_file = '/etc/mtab';

sub are_nfs_mounts_on_system {
    return is_filesystem_mounted_on_system('nfs');
}

sub are_xfs_mounts_on_system {
    return is_filesystem_mounted_on_system('xfs');
}

sub is_filesystem_mounted_on_system {
    my $fstype = shift;
    return 0 unless $fstype;

    my $fh;

    # TODO: FIXME: This is likely very slow
    open( $fh, '<', $mtab_file ) or die "Cannot open :$mtab_file:";

    while ( my $line = <$fh> ) {
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        next if $line =~ m/^#/;
        next if length($line) == 0;
        my ( $device, $mount_point, $filesys_type, $options, $fs_freq, $fs_passno ) = split( /\s+/, $line );
        if ( $filesys_type && $filesys_type =~ m/\b$fstype\b/i ) {
            close($fh);
            return 1;
        }
    }
    close($fh);

    return 0;
}

1;
