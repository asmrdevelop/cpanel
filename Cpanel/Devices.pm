
# cpanel - Cpanel/Devices.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Devices;

use strict;
use warnings;

use File::Basename ();

use Cpanel::Filesys::FindParse ();
use Cpanel::Filesys::Mounts    ();

=head1 NAME

Cpanel::Devices

=head1 DESCRIPTION

Utility functions for discovering what device actually backs a file, and what device we are actually configured in fstab to use to back a file.

=head1 SYNOPSIS

    require Cpanel::Devices;
    my ($rdev, $ruuid) = Cpanel::Devices::get_device_for_file("/");
    my ($cdev, $cuiid) = Cpanel::Devices::get_configured_device_for_file("/"));
    print "disk has changed out from under us" if $rdev ne $cdev || $ruiid ne $cuiid;

=head1 FUNCTIONS

=head2 get_device_for_file

    (STRING $device,STRING $uuid) = get_device_for_file(STRING $file)

Returns the relevant device and uuid which is underlying the provided file's mount point.

=cut

sub get_device_for_file {
    my ($file) = @_;
    $file =~ tr{/}{}s;    # collapse duplicate /s
    die "no such entry '$file' in filesystem." unless -e $file;

    my %tab = get_mountpoints_from_mtab();
    return _get_dev_and_uuid_from_entries( $file, %tab );
}

=head2 get_configured_device_for_file

    (STRING $device, STRING $uuid) = get_configured_device_for_file(STRING $file)

Return the device which is currently configured in /etc/fstab (rather than what is actually used) to back the provided file.

=cut

sub get_configured_device_for_file {
    my ($file) = @_;
    $file =~ tr{/}{}s;    # collapse duplicate /s
    die "no such entry '$file' in filesystem." unless -e $file;

    my %tab = get_mountpoints_from_fstab();
    return _get_dev_and_uuid_from_entries( $file, %tab );
}

sub _get_dev_and_uuid_from_entries {
    my ( $file, %tab ) = @_;
    my $used_mp = get_mountpoint_for_file( $file, keys(%tab) );
    return 0 unless $used_mp && $tab{$used_mp};

    #Deal with GPT tables first
    if ( $tab{$used_mp}{gptuuid} ) {
        return ( get_dev_for_gptuuid( $tab{$used_mp}{gptuuid} ), $tab{$used_mp}{gptuuid} );
    }
    elsif ( $tab{$used_mp}{gptlabel} ) {
        return ( $tab{$used_mp}{partition}, get_gptuuid_for_dev( $tab{$used_mp}{partition} ) );
    }

    return $tab{$used_mp}{uuid} ? ( get_dev_for_uuid( $tab{$used_mp}{uuid} ), $tab{$used_mp}{uuid} ) : ( $tab{$used_mp}{partition}, get_uuid_for_dev( $tab{$used_mp}{partition} ) );
}

=head2 get_mountpoints_from_mtab, get_mountpoints_from_fstab

    HASH %mountpoints = get_mountpoints_from_fstab();
    HASH %mountpoints_real = get_mountpoints_from_mtab();

List the available mount points on the system, both configured and real.

=cut

my %entries;

sub get_mountpoints_from_fstab {
    return %entries if %entries;
    return %entries = _get_mountpoints_from_tab();
}

my %entries_real;

sub get_mountpoints_from_mtab {
    return %entries_real if %entries_real;
    return %entries_real = _get_mountpoints_from_tab( Cpanel::Filesys::Mounts::get_mounts_without_jailed_filesystems() );
}

sub _get_mountpoints_from_tab {
    my $tabfile = shift;
    my %tab     = map {
        ( $_->{uuid} )  = $_->{partition} =~ m/^UUID=(.*)$/;
        ( $_->{label} ) = $_->{partition} =~ m/^LABEL=(.*)$/;

        #Handle those unfortunates out there with GPT partition tables
        ( $_->{gptuuid} )  = $_->{partition} =~ m/^PARTUUID=(.*)$/;
        ( $_->{gptlabel} ) = $_->{partition} =~ m/^PARTLABEL=(.*)$/;

        $_->{partition} = get_dev_for_label( $_->{label} )       if $_->{label};
        $_->{partition} = get_dev_for_gptlabel( $_->{gptlabel} ) if $_->{gptlabel};

        #Ultimately if we can't figure out the partition, leave it undef -- we are comparing this later, and undef is as good as any guess.
        $_->{partition} = File::Basename::basename( $_->{partition} ) if $_->{partition};
        $_->{mountpoint} => $_
    } Cpanel::Filesys::FindParse::parse_fstab($tabfile);
    return %tab;
}

=head2 get_dev_for_uuid

    STRING $device = get_dev_for_uuid(STRING $uuid)

Return the device in /dev which corresponds to the provided disk UUID.

=cut

sub get_dev_for_uuid {
    my ($uuid) = @_;
    my $target = readlink "/dev/disk/by-uuid/$uuid";
    return $target if !length $target;
    return File::Basename::basename($target);
}

=head2 get_dev_for_gptuuid

    STRING $device = get_dev_for_gptuuid(STRING $uuid)

Return the device in /dev which corresponds to the provided GPT disk UUID.

=cut

sub get_dev_for_gptuuid {
    my ($uuid) = @_;
    my $target = readlink "/dev/disk/by-partuuid/$uuid";
    return $target if !length $target;
    return File::Basename::basename($target);
}

=head2 get_dev_for_label

    STRING $device = get_dev_for_label(STRING $label)

Return the device in /dev which corresponds to the provided disklabel

=cut

sub get_dev_for_label {
    my ($label) = @_;
    my $target = readlink "/dev/disk/by-label/$label";
    return $target if !length $target;
    return File::Basename::basename($target);
}

=head2 get_dev_for_gptlabel

    STRING $device = get_dev_for_gptlabel(STRING $label)

Return the device in /dev which corresponds to the provided GPT disklabel

=cut

sub get_dev_for_gptlabel {
    my ($label) = @_;
    my $target = readlink "/dev/disk/by-partlabel/$label";
    return $target if !length $target;
    return File::Basename::basename($target);
}

=head2 get_uuid_for_dev, get_gptuuid_for_dev

    STRING $uuid = get_uuid_for_dev(STRING $dev)
    STRING $uuid = get_gptuuid_for_dev(STRING $dev)

Return the uuid in /dev/disk/by-[gpt]uuid which corresponds to the provided disk in /dev/.

=cut

sub get_uuid_for_dev {
    return _get_uuid( $_[0], 'uuid' );
}

sub get_gptuuid_for_dev {
    return _get_uuid( $_[0], 'partuuid' );
}

sub _get_uuid {
    my ( $dev, $type ) = @_;
    opendir( my $dh, "/dev/disk/by-$type" ) || return '';
    my @all_uuids = readdir($dh);
    foreach my $link (@all_uuids) {
        my $dv = readlink "/dev/disk/by-$type/$link";
        next unless $dv && $dev eq File::Basename::basename($dv);
        return File::Basename::basename($link);
    }
    return '';
}

=head2 get_mountpoint_for_file

    STRING $mountpoint = get_mountpoint_for_file(STRING $file, ARRAY @mountpoints)

Utility method to correctly pick which mountpoint is actually backing a particular file path.

=cut

sub get_mountpoint_for_file {
    my ( $file, @mountpoints ) = @_;

    #Get the shortest possible mountpoint which contains this file
    return ( sort { length($b) <=> length($a) } grep { index( $file, $_ ) == 0 } @mountpoints )[0];
}

1;
