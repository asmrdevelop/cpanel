package Cpanel::Filesys::Info;

# cpanel - Cpanel/Filesys/Info.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::Filesys::Info

=cut

use strict;
use warnings;

use Cpanel::StatCache       ();
use Cpanel::Filesys::Mounts ();

our $VERSION = '1.4';

our $FSTAB_FILE = '/etc/fstab';

our $DF_CACHE_TTL = 180;

# minimum number of available blocks required
our ( $cached_time, $statfs_disabled ) = (0);
our (%filesys_hash);

our @FILESYSTEM_TYPES_TO_SKIP = qw(
  autofs
  cifs
  devpts
  nfs
  proc
  rpc_pipefs
  rootfs
  smbfs
  sysfs
  tmpfs
);

our @FILESYSTEM_MOUNT_ROOTS_TO_REJECT = qw(
  dev
  proc
  sys
  var/cagefs
);

## returns hash (Filesys::Df::df or '/bin/df' info) for given $mount_point
sub filesystem_info {
    my $mount_point = shift;

    return if ( !$mount_point || !Cpanel::StatCache::cachedmtime($mount_point) );

    if ( my $ret = $Cpanel::Filesys::Info::filesys_hash{$mount_point} ) {
        return wantarray ? %$ret : $ret;
    }

    my $df_ref;
    if ( !statfs_disabled() ) {
        $df_ref = df( $mount_point, 1024 );
    }

    my $last_seen_mount_point;
    if ( defined $df_ref && ( exists $df_ref->{'bavail'} || exists $df_ref->{'bfree'} ) ) {
        $last_seen_mount_point = _populate_filesys_hash_from_filesys_df( $mount_point, $df_ref );
    }
    else {
        # use df output
        $last_seen_mount_point = _populate_filesys_hash_from_df( 'want_boot' => 1, 'mount_point' => $mount_point );
    }

    my $ret = $Cpanel::Filesys::Info::filesys_hash{$last_seen_mount_point};
    return wantarray ? %$ret : $ret;
}

## returns hash for all mount points ($mount => 'Cpanel::Filesys::Mounts::get_mounts_file_path()', Filesys::Df::df, and '/bin/df' info)
sub _all_filesystem_info {
    my %OPTS = @_;
    if ( time() - $cached_time < 30 ) {
        return _filesys_hash_return( %OPTS, 'wantarray' => wantarray() );
    }
    $cached_time = time();

    if ( !statfs_disabled() ) {
        my $slash_df_ref = df( '/', 1024 );
        my $lines_ref    = Cpanel::Filesys::Mounts::get_mounts_without_jailed_filesystems();
        if ( defined $slash_df_ref && ( exists $slash_df_ref->{'bavail'} || exists $slash_df_ref->{'bfree'} ) ) {
            my %seen;

            my $fs_exclude_regexp = _make_fs_exclude_regexp();
            foreach my $procmount_line ( split( m{\n}, $$lines_ref ) ) {
                my ( $device, $mount_point, $fstype, $_mode ) = split( /\s+/, $procmount_line );

                next if $seen{$mount_point};
                next if _should_exclude_mount_point( $mount_point, $fs_exclude_regexp );
                next if grep { $_ eq $fstype } @FILESYSTEM_TYPES_TO_SKIP;

                $seen{$mount_point} = 1;
                my $df_ref = $mount_point eq '/' ? $slash_df_ref : df( $mount_point, 1024 );

                if ( defined $df_ref && ( exists $df_ref->{'bavail'} || exists $df_ref->{'bfree'} ) ) {
                    $filesys_hash{$mount_point}{'device'} = $device;
                    $filesys_hash{$mount_point}{'_mode'}  = $_mode;
                    $filesys_hash{$mount_point}{'fstype'} = $fstype;
                    _populate_filesys_hash_from_filesys_df( $mount_point, $df_ref );
                }
            }
        }
        else {
            $statfs_disabled = 1;    #if Filesys::Df can't df / something is wrong
        }
    }
    else {
        $statfs_disabled = 1;
    }

    # use df output
    if ($statfs_disabled) {
        _populate_filesys_hash_from_df(%OPTS);
    }

    return _filesys_hash_return( %OPTS, 'wantarray' => wantarray() );
}

sub _filesys_hash_return {
    my (%OPTS) = @_;

    #
    # Only return entries that have a device since
    # Cpanel::Filesys can augment our cache
    #
    # If the 'want_boot' flag is passed then
    # we allow /boot to be returned
    #
    my $ref = {
        map { !exists $filesys_hash{$_}{'device'} || ( !$OPTS{'want_boot'} && $_ eq '/boot' ) ? () : ( $_ => $filesys_hash{$_} ) }
          keys %filesys_hash
    };

    return $OPTS{'wantarray'} ? %$ref : $ref;
}

sub _make_fs_exclude_regexp {
    return join( '|', map { quotemeta $_ } @FILESYSTEM_MOUNT_ROOTS_TO_REJECT );

}

sub _should_exclude_mount_point {
    my ( $mount_point, $fs_exclude_regexp ) = @_;
    return 1 if $mount_point =~ m{^/(?:$fs_exclude_regexp)(?:/|$)};
    return 1 if $mount_point =~ m{/(?:cagefs|virtfs)/};
    return 0;
}

sub _populate_filesys_hash_from_df {
    my (%OPTS) = @_;
    my $fs_exclude_regexp = _make_fs_exclude_regexp();

    ## case 33663: uses -P
    # Do not combine the following two lines. If the output of cachedmcommand is used directly in the
    # split we get an intermittent crash in Cpanel::Logger relating to "-t STDOUT".
    #
    #
    my @df_args = $OPTS{'mount_point'} ? ( $OPTS{'mount_point'} ) : ();

    my $last_seen_mount_point;

    require Cpanel::CachedCommand;
    my $df_cmd = Cpanel::CachedCommand::cachedmcommand( $DF_CACHE_TTL, '/bin/df', '-P', '-k', '-l', @df_args );
    my @df     = split( /\n/, $df_cmd );
    foreach my $line (@df) {
        if ( $line =~ m/^\s*(\/\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([0-9]+)\S*\s+(\S+)/ ) {
            my ( $device, $blocks, $blocks_used, $blocks_free, $percent_used, $mount_point ) = ( $1, $2, $3, $4, $5, $6 );
            next if _should_exclude_mount_point( $mount_point, $fs_exclude_regexp );

            $last_seen_mount_point                      = $mount_point;
            $filesys_hash{$mount_point}{'device'}       = $device;
            $filesys_hash{$mount_point}{'filesystem'}   = $mount_point;
            $filesys_hash{$mount_point}{'blocks'}       = $blocks;
            $filesys_hash{$mount_point}{'blocks_used'}  = $blocks_used;
            $filesys_hash{$mount_point}{'blocks_free'}  = $blocks_free;
            $filesys_hash{$mount_point}{'percent_used'} = $percent_used;
            $filesys_hash{$mount_point}{'mount_point'}  = $mount_point;
        }
    }

    ## case 33663: uses -P
    # Do not combine the following two lines. If the output of cachedmcommand is used directly in the
    # split we get an intermittent crash in Cpanel::Logger relating to "-t STDOUT".
    $df_cmd = Cpanel::CachedCommand::cachedmcommand( $DF_CACHE_TTL, '/bin/df', '-P', '-i', '-l', @df_args );
    @df     = split( /\n/, $df_cmd );
    foreach my $line (@df) {
        if ( $line =~ m/^\s*(\/\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([0-9]+)\S*\s+(\S+)/ ) {
            my ( $device, $inodes, $inodes_used, $inodes_free, $inodes_percent_used, $mount_point ) = ( $1, $2, $3, $4, $5, $6 );
            next if _should_exclude_mount_point( $mount_point, $fs_exclude_regexp );

            $last_seen_mount_point = $mount_point;
            $filesys_hash{$mount_point}{'device'}      ||= $device;
            $filesys_hash{$mount_point}{'filesystem'}  ||= $mount_point;
            $filesys_hash{$mount_point}{'mount_point'} ||= $mount_point;
            $filesys_hash{$mount_point}{'inodes'}              = $inodes;
            $filesys_hash{$mount_point}{'inodes_used'}         = $inodes_used;
            $filesys_hash{$mount_point}{'inodes_free'}         = $inodes_free;
            $filesys_hash{$mount_point}{'inodes_percent_used'} = $inodes_percent_used;
        }
    }

    return $last_seen_mount_point;
}

sub _populate_filesys_hash_from_filesys_df {
    my ( $mount_point, $df_ref ) = @_;

    $filesys_hash{$mount_point}{'blocks'}       = $df_ref->{'blocks'};
    $filesys_hash{$mount_point}{'blocks_used'}  = $df_ref->{'used'};
    $filesys_hash{$mount_point}{'blocks_free'}  = exists $df_ref->{'bavail'} ? $df_ref->{'bavail'} : $df_ref->{'bfree'};
    $filesys_hash{$mount_point}{'percent_used'} = $df_ref->{'per'};
    $filesys_hash{$mount_point}{'mount_point'}  = $mount_point;
    $filesys_hash{$mount_point}{'filesystem'} ||= $mount_point;
    $filesys_hash{$mount_point}{'inodes'}              = $df_ref->{'files'};
    $filesys_hash{$mount_point}{'inodes_used'}         = $df_ref->{'fused'};
    $filesys_hash{$mount_point}{'inodes_free'}         = exists $df_ref->{'favail'} ? $df_ref->{'favail'} : $df_ref->{'ffree'};
    $filesys_hash{$mount_point}{'inodes_percent_used'} = $df_ref->{'fper'};

    return $mount_point;
}

sub statfs_disabled {
    if ( !defined $statfs_disabled ) {
        $statfs_disabled = Cpanel::StatCache::cachedmtime('/var/cpanel/disablestatfs') ? 1 : 0;
    }
    return $statfs_disabled;
}

sub df {
    require Filesys::Df;
    return Filesys::Df::df(@_);
}

sub is_filesystem_overlay {
    my ( $partitions, $mount ) = @_;
    return $partitions->{$mount}{'fstype'} =~ /overlay|union/;
}

1;
