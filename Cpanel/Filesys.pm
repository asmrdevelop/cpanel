package Cpanel::Filesys;

# cpanel - Cpanel/Filesys.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Filesys

=cut

use strict;
use warnings;

use Cpanel::Filesys::Info            ();
use Cpanel::Filesys::FindParse       ();
use Cpanel::Validate::FilesystemPath ();
use Cpanel::SafeRun::Simple          ();

our $VERSION = '2.0';

*_all_filesystem_info = *Cpanel::Filesys::Info::_all_filesystem_info;
*statfs_disabled      = *Cpanel::Filesys::Info::statfs_disabled;
*find_mount           = *Cpanel::Filesys::FindParse::find_mount;

=head2 filesystem_info_from_file

If you need to know the filesystem where a particular file resides, use this
function. It returns the filesystem in question, plus information about it.
It's equivalent to running `df -P $file` from the command line.

=head3 Arguments

=over

=item $filename

The full path to the file whose residence is unknown to you.

=back

=head3 Returns

A hashref containing information about the filesystem that contains the file
given. For /bin/rm, it  looks like this:

  {
      'blocks'       => '41926416',  # Total size in KiB
      'blocks_free'  => '14512868',  # in KiB
      'blocks_used'  => '27413548',  # in KiB
      'device'       => '/dev/vda1',
      'filesystem'   => '/',         # the actual filesystem
      'mount_point'  => '/',         # where the filesystem is mounted, which
                                     # might be different! (e.g., virtfs)
      'percent_used' => '66',
  }

=cut

sub filesystem_info_from_file {
    my ($filename) = @_;
    my $mount = {};

    # Forbids all invalid filenames and prevents directory traversal.
    # We are not shelling out, so things like pipes and redirects are safe.
    Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes($filename);

    # Example `df -P` output:
    # Filesystem     1024-blocks   Used Available Capacity Mounted on
    # /dev/sda2           487634 177936    280002      39% /boot
    my $df_p = [ split /\n/, Cpanel::SafeRun::Simple::saferunnoerror( '/bin/df', '-P', $filename ) ];

    return $mount unless defined $df_p->[1];
    if ( $df_p->[1] =~ m/^\s*(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([0-9]+)\S*\s+(\S+)/ ) {
        my ( $device, $blocks, $blocks_used, $blocks_free, $percent_used, $mount_point ) = ( $1, $2, $3, $4, $5, $6 );

        $mount->{'device'}       = $device;
        $mount->{'filesystem'}   = $mount_point;
        $mount->{'blocks'}       = $blocks;
        $mount->{'blocks_used'}  = $blocks_used;
        $mount->{'blocks_free'}  = $blocks_free;
        $mount->{'percent_used'} = $percent_used;
        $mount->{'mount_point'}  = $mount_point;
    }

    return $mount;
}

sub getmntpoint {
    require Cpanel::Filesys::Home;
    goto \&Cpanel::Filesys::Home::get_homematch_with_most_free_space;
}

sub get_homematch_with_most_free_space {
    require Cpanel::Filesys::Home;
    goto \&Cpanel::Filesys::Home::get_homematch_with_most_free_space;
}

1;
