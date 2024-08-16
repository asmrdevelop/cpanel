package Cpanel::DiskLib;

# cpanel - Cpanel/DiskLib.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Filesys::Info ();

sub get_disk_used_percentage_with_dupedevs {
    my $filesys_ref = Cpanel::Filesys::Info::_all_filesystem_info( 'want_boot' => 1 );

    my @disks;
    foreach my $mount ( keys %$filesys_ref ) {
        next if index( $mount, '/usr/share/cagefs-skeleton' ) == 0;

        my $disk = $filesys_ref->{$mount}{'device'};
        $disk =~ s/^\/dev\///;
        next if $disk =~ m/^loop/ && $mount =~ m/^\/snap\//;    # Ignore /snap/ mounts from loopback mounts
        push @disks,
          {
            'filesystem' => $filesys_ref->{$mount}{'filesystem'},
            'disk'       => $disk,
            'device'     => $filesys_ref->{$mount}{'device'},
            'percentage' => $filesys_ref->{$mount}{'percent_used'},
            'total'      => $filesys_ref->{$mount}{'blocks'},
            'used'       => $filesys_ref->{$mount}{'blocks_used'},
            'available'  => $filesys_ref->{$mount}{'blocks_free'},

            'inodes_ipercentage' => $filesys_ref->{$mount}{'inodes_percent_used'},
            'inodes_total'       => $filesys_ref->{$mount}{'inodes'},
            'inodes_used'        => $filesys_ref->{$mount}{'inodes_used'},
            'inodes_available'   => $filesys_ref->{$mount}{'inodes_free'},

            'mount' => $filesys_ref->{$mount}{'mount_point'},
          };
    }
    return \@disks;
}

sub get_disk_used_percentage {
    my $disks_ref = get_disk_used_percentage_with_dupedevs();
    my %diskfree  = map { $_->{'device'} => $_ } @{$disks_ref};
    return wantarray ? %diskfree : \%diskfree;
}

1;
