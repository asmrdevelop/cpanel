package Cpanel::Filesys::FindParse;

# cpanel - Cpanel/Filesys/FindParse.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Filesys::FindParse

=cut

use strict;
use warnings;

use Cpanel::StringFunc::Match ();

our $FSTAB_FILE = '/etc/fstab';

=head2 parse_fstab([$file])

Parses the given file, or /etc/fstab if no file is specified.

Returns an array containing hashrefs with entries for mountpoint, partition
(which may be a LABEL= or UUID= entry), fstype, and options (an arrayref).

=cut

sub parse_fstab {
    my $fstab = shift || $FSTAB_FILE;
    my @mount_points;
    if ( open my $fh_fstab, '<', $fstab ) {
        while ( my $line = <$fh_fstab> ) {
            next if $line =~ /^\s*#/;
            if ( my ( $partition, $mntpoint, $fstype, $options ) = $line =~ /^\s*(\S+)\s+(\S+)\s+(\S+)\s*(\S*)/ ) {
                $mntpoint =~ s/^(.+)\/+$/$1/;

                # Note that the partition could be a UUID or a label.  We don't
                # dereference that in any way here, although that could be a
                # future option.
                push @mount_points,
                  {
                    mountpoint => $mntpoint,
                    partition  => $partition,
                    fstype     => $fstype,
                    options    => [ split /\s*,\s*/, $options ],
                  };
            }
        }
        close($fh_fstab);
    }
    else {
        return undef;
    }
    return @mount_points;
}

sub find_mount {
    my ( $partitions, $directory ) = @_;

    $directory =~ tr{/}{}s;    # collapse duplicate /s

    if ( -l $directory ) {
        require Cpanel::Readlink;
        $directory = Cpanel::Readlink::deep($directory);
    }

    if ( ref $partitions eq 'HASH' ) {    #AKA Cpanel::Filesys::Info::_all_filesystem_info, Cpanel::DiskLib::get_disk_used_percentage
        if ( values %{$partitions} && defined( ( values %{$partitions} )[0]->{'used'} ) ) {    # Cpanel::DiskLib::get_disk_used_percentage
            foreach my $mount ( sort { length $partitions->{$b}->{'mount'} <=> length $partitions->{$a}->{'mount'} } keys %{$partitions} ) {
                if ( Cpanel::StringFunc::Match::beginmatch( $directory, $partitions->{$mount}->{'mount'} . '/' ) or $directory eq $partitions->{$mount}->{'mount'} ) {
                    return $partitions->{$mount}->{'mount'};
                }
            }

        }
        else {
            foreach my $mount ( sort { length $b <=> length $a } keys %{$partitions} ) {    # Cpanel::Filesys::Info::_all_filesystem_info
                if ( Cpanel::StringFunc::Match::beginmatch( $directory, $mount . '/' ) or $directory eq $mount ) {
                    return $mount;
                }
            }
        }
    }
    else {    #AKA Cpanel::DiskLib::get_disk_used_percentage_with_dupedevs, get_disk_mounts_arrayref
        foreach my $mount ( sort { length $b->{'mount'} <=> length $a->{'mount'} } @{$partitions} ) {
            if ( Cpanel::StringFunc::Match::beginmatch( $directory, $mount->{'mount'} . '/' ) or $directory eq $mount->{'mount'} ) {
                return $mount->{'mount'};
            }
        }
    }
    return '/';
}

1;
