
# cpanel - Cpanel/Quota/Filesys.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Quota::Filesys;

use strict;
use Cpanel::Filesys::Mounts ();
use Cpanel::Filesys::Root   ();

=head1 NAME

Cpanel::Quota::Filesys

=head1 DESCRIPTION

This module is intended to be used as a base class for
Cpanel::Quota::Common or a standalone module for
fetching information about which filesystems have quota enabled

It is designed to be a functional replacement for the
Quota::getmntent and Quota::getqcarg which have the following
problems:

Quota::getmntent - reads /etc/mtab which turns out to be out
of sync with /proc/mounts on many Cent5/Cent6 systems.

Quota::getqcarg - re-reads the entire mounts table and stats
compares every mount point.  This function exponentially
slows with the number of mount points.

=head1 SYNOPSIS

  my $fs        = Cpanel::Quota::Filesys->new();
  my $paths_ref = $fs->get_devices_with_quotas_enabled();

  foreach my $dev ( sort keys %{$paths_ref} ) {
    my $type = $paths_ref->{$dev}{'fstype'};
    my $mode = $paths_ref->{$dev}{'mode'}; # sometimes called options
    my $mountpoint = $paths_ref->{$dev}{'mountpoint'};
    my $lookupdev = $paths_ref->{$dev}{'lookupdev'};
  }

=cut

# from bin/quota
our $quota_ignore_file = '/var/cpanel/noquotafs';

# from bin/quota
my %vzfs_devices = (
    '/dev/vzfs'  => 1,
    '/dev/simfs' => 1,
);

# from Cpanel::Filesys::Info
our %FILESYSTEM_TYPES_TO_SKIP = (
    'rootfs'      => 1,
    'autofs'      => 1,
    'lofs'        => 1,
    'ignore'      => 1,
    'cifs'        => 1,
    'devpts'      => 1,
    'none'        => 1,
    'proc'        => 1,
    'devtmpfs'    => 1,
    'procfs'      => 1,
    'securityfs'  => 1,
    'cgroup'      => 1,
    'pstore'      => 1,
    'configfs'    => 1,
    'rpc_pipefs'  => 1,
    'mqueue'      => 1,
    'systemd-1'   => 1,
    'smbfs'       => 1,
    'sysfs'       => 1,
    'hugetlbfs'   => 1,
    'binfmt_misc' => 1,
    'tmpfs'       => 1,
);

# from Cpanel::Filesys::Info
our @FILESYSTEM_MOUNT_ROOTS_TO_REJECT = qw(
  dev
  proc
  sys
  var/cagefs
);

our $READ_BUFFER_SIZE = 131072;    # 2 ** 17

# The READ_BUFFER_SIZE should be large enough that we
# can probably read in the whole file in one read()
# but does not use too much memory in case we cannot

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

=head1 METHODS

=head2 get_devices_with_quotas_enabled()

Gets a list of the of devices along with the information we need
to know to support quotas that have quota support.

=head3 Arguments

None.

=head3 Return Value

a hashref    A list of devices upon which the module can operate.

=head3 Example Format

  {
     '/dev/hda3' => {
        'fstype'     => 'ext3',
        'mode'       => 'usrquota',
        'mountpoint' => '/',
        'lookupdev' => '/dev/hda3',
     },
     '/dev/hda2' => {
        'fstype'     => 'ext3',
        'mode'       => 'usrquota',
        'mountpoint' => '/tmp',
        'lookupdev' => '/dev/hda2',
      },
      '/dev/hda5' => {
        'fstype'     => 'xfs',
        'mode'       => 'usrquota',
        'mountpoint' => '/archive',
        'lookupdev'  => '(XFS)/dev/hda5',
      }

  }

=cut

sub get_devices_with_quotas_enabled {
    my ($self) = @_;
    $self->_get_quota_paths() if !$self->{paths_info};
    return { map { $_ => $self->{paths_info}{$_} } @{ $self->{'paths'} } };
}

=head2 get_all_paths()

Gets a list of the unfiltered paths that are available. This is solely for informative purposes
and modifications to this list will not have any affect on the saved list of paths. Moreover,
not all of these paths will have quotas enabled. Use get_paths (after setting a user) to see the
filtered list of paths that do have quotas enabled and use set_paths to alter the list.

=head3 Arguments

None.

=head3 Return Value

array of strings    A list of available paths upon which the module can operate.

=cut

sub get_all_paths {
    my ($self) = @_;
    $self->_get_quota_paths() if !$self->{paths_unfiltered};
    return @{ $self->{paths_unfiltered} };
}

=head2 get_paths()

Gets a list of the filtered paths that will be acted upon. This is solely for informative purposes
and modifications to the returned list will not have any affect on the saved list of paths. Use
set_paths to alter the list properly. Note: A user must be set for proper filtering to take place
and this method will die when that requirement isn't met.

=head3 Arguments

None.

=head3 Return Value

array of strings    A list of paths upon which the module will operate.

=cut

sub get_paths {
    my $self = shift;

    $self->_get_quota_paths() if !$self->{paths};

    if ( defined $self->{limits} ) {
        return @{ $self->{paths} };
    }
    elsif ( defined $self->{uid} ) {
        $self->get_limits();
        return @{ $self->{paths} };
    }
    else {
        die('Paths cannot be validated until a user is set.') if !$self->{limits};
    }
    return;
}

=head2 get_device_arg_for_quota_module_for_path()

Returns the device argument for a given path that can be used with the Quota.pm module

=head3 Arguments

A path from the get_paths or get_all_paths call

=head3 Return Value

a string     - The device argument to be used with the quota module

=cut

sub get_device_arg_for_quota_module_for_path {
    my ( $self, $dev ) = @_;

    my $lookupdev = $self->{'paths_info'}{$dev}{'lookupdev'} or die("get_device_arg_for_quota_module_for_path failed because lookupdev is missing for “$dev”");

    return $lookupdev;
}

=head2 quotas_are_enabled()

Determine if quotas are enabled on any filesystem in the paths list.

=head3 Arguments

none

=head3 Return Value

1 - Quotas are enabled on at least one filesystem that this module knows about
0 - Quotas are not enabled on any filesystem that this module knows about

=cut

sub quotas_are_enabled {
    my ($self) = @_;

    $self->_get_quota_paths() if !$self->{paths};
    return @{ $self->{'paths'} } ? 1 : 0;
}

sub _get_quota_paths {
    my ($self) = @_;

    $self->{'paths_unfiltered'} = [];
    $self->{'paths'}            = [];
    $self->{'paths_info'}       = {};

    # The system quota binary perfers to read /proc/mounts
    # so lets do that as well
    my $lines_ref         = Cpanel::Filesys::Mounts::get_mounts_without_jailed_filesystems();
    my $fs_exclude_regexp = join( '|', map { quotemeta $_ } @FILESYSTEM_MOUNT_ROOTS_TO_REJECT );
    my %seen_devices;
    my %seen_vzfs_devices;    # only check quota on the first vzfs device

  FSLINE:
    foreach my $procmount_line ( split( m{\n}, $$lines_ref ) ) {
        next
          if index( $procmount_line, 'cgroup ' ) == 0
          || index( $procmount_line, 'pstore ' ) == 0
          || index( $procmount_line, 'configfs ' ) == 0
          || index( $procmount_line, 'procfs ' ) == 0
          || index( $procmount_line, 'mqueue ' ) == 0
          || index( $procmount_line, 'tmpfs ' ) == 0
          || index( $procmount_line, 'devtmpfs ' ) == 0
          || index( $procmount_line, 'hugetlbfs ' ) == 0;

        my ( $device, $mount_point, $fstype, $mode ) = split( /\s+/, $procmount_line );

        next if !length $device || !length $mode;

        if ( $device eq $Cpanel::Filesys::Root::DEV_ROOT && !-e $device ) {
            $device = Cpanel::Filesys::Root::get_root_device_path();
        }

        next if $seen_devices{$device}++                      ||    # already seen
          $FILESYSTEM_TYPES_TO_SKIP{$fstype}                  ||    # from Cpanel::Filesys::Info
          index( $fstype, 'auto.' ) == 0                      ||    # no auto
          $mount_point =~ m{^/(?:$fs_exclude_regexp)(?:/|$)}o ||    # from Cpanel::Filesys::Info
          _ignore( $device, $fstype );                              # from bin/quota

        push @{ $self->{'paths_unfiltered'} }, $device;
        $self->{'paths_info'}{$device} = {
            'fstype'     => $fstype,
            'mode'       => $mode,
            'mountpoint' => $mount_point,
        };
        $self->_augment_path_info_with_lookupdev($device);

        if ( $vzfs_devices{$device} ) {

            # from bin/quota
            # If we've seen one VZ file system, we've seen them all.
            # if they have /dev/vzfs and /dev/simfs we must
            # avoid reading both or we will show 2x the disk usage
            foreach my $vzfs_device ( keys %vzfs_devices ) {
                next FSLINE if $seen_vzfs_devices{$vzfs_device};
            }

            $seen_vzfs_devices{$device} = 1;
        }
        if ( $mode && $mode =~ m{quota}i && $mode !~ m{no[a-z]*quota}i ) {
            push @{ $self->{'paths'} }, $device;
        }

    }

    @{ $self->{'paths_unfiltered'} } = sort @{ $self->{'paths_unfiltered'} };
    @{ $self->{'paths'} }            = sort @{ $self->{'paths'} };

    return;
}

my $loaded_ignore_list_if_exists = 0;
my %ignore_list                  = ();

# from bin/quota
sub _ignore {
    my ( $dev, $type ) = @_;

    return if !$type;

    my $lc_type = lc $type;

    return 1 if index( $lc_type, 'nfs' ) != 0 && $dev =~ m{^[^/:]+:};

    if ( !$loaded_ignore_list_if_exists ) {
        if ( -f $quota_ignore_file && !-z _ ) {
            my $fh;
            open( $fh, '<', $quota_ignore_file ) || die "Unable to read $quota_ignore_file: $!";
            local $/;
            %ignore_list = map { my $t = lc($_); $t =~ s/\s+//; $t => 1 } split /\n/, <$fh>;
            close $fh;
        }
        $loaded_ignore_list_if_exists = 1;
    }
    return $ignore_list{$lc_type} ? 1 : undef;
}

sub _clear_ignore_list_cache {
    %ignore_list                  = ();
    $loaded_ignore_list_if_exists = 0;
    return;
}

sub _augment_path_info_with_lookupdev {
    my ( $self, $device ) = @_;

    my $lookupdev = $device;
    my $mode      = $self->{'paths_info'}{$device}{'mode'};
    my $fstype    = $self->{'paths_info'}{$device}{'fstype'};
    $fstype =~ tr{A-Z}{a-z};

    if ( index( $mode, 'loop=' ) > -1 && $mode =~ m{(?:^|,)loop=([^\,]+)} ) {
        $lookupdev = $1;
    }

    if ( $fstype eq 'xfs' ) {
        $lookupdev = '(XFS)' . $lookupdev;
    }
    elsif ( $fstype eq 'vxfs' ) {
        $lookupdev = '(VXFS)' . $lookupdev;
    }
    elsif ( $fstype eq 'afs' ) {
        $lookupdev = '(AFS)' . $lookupdev;
    }
    elsif ( $fstype eq 'jfs2' ) {
        $lookupdev = '(JFS2)' . $lookupdev;
    }
    elsif ( $fstype eq 'nfs' && $device =~ m{^(/.*)\@([^/]+)$} ) {
        $lookupdev = "$2:$1";    # converts old style nfs to new style nfs (@ -> :)
    }

    $self->{'paths_info'}{$device}{'lookupdev'} = $lookupdev;

    return 1;
}

1;
