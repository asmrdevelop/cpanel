
# cpanel - Cpanel/Filesys/Mounts.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Filesys::Mounts;

use strict;
use warnings;

use Cpanel::LoadFile             ();
use Cpanel::CachedCommand::Utils ();
use Cpanel::Debug                ();
use Cpanel::StatCache            ();
use Try::Tiny;

# minimum number of available blocks required
our (%fsmap);

our $FSTAB_FILE            = '/etc/fstab';
our $MTAB_FILE             = '/etc/mtab';
our $PROC_MOUNTS_FILE      = '/proc/mounts';
our $PROC_MOUNT_STATS_FILE = '/proc/self/mountstats';
our $MOUNTS_CACHE          = 'MOUNTS_CACHE';
our $MOUNTS_CACHE_TTL      = ( 15 * 60 );               # Fifteen minute cache

my %EXCLUDE_MOUNTS = (
    '/proc' => 1,
    '/dev'  => 1,
    '/boot' => 1,
    '/sys'  => 1,

);
my %EXCLUDE_FS = (
    'tmpfs'  => 1,
    'nfs'    => 1,
    'smbfs'  => 1,
    'cifs'   => 1,
    'devpts' => 1,
    'proc'   => 1,
    'procfs' => 1,
    'sysfs'  => 1,
);

# Mounts need to be unescaped
# space (\040), tab (\011), newline (\012)  and  back-slash  (\134)
my %mount_unescapes = ( '040' => " ", '011' => "\t", "134" => "\\", "012" => "\n" );

=head1 NAME

Cpanel::Filesys::Mounts

=head2 get_mount_file_path

Returns the best path for the mounts files
We prefer /proc/mounts over /etc/mtab because
the system quota binary prefers /proc/mounts over /etc/mtab

=head3 Arguments

None

=head3 Return Value

a string     - The path to the mounts file

=cut

our $cached_mounts_file;
our $mounts_cache;

sub get_mounts_file_path {
    return (
        $cached_mounts_file ||= (
            -r $PROC_MOUNTS_FILE
            ? $PROC_MOUNTS_FILE
            : $MTAB_FILE
        )
    );

}

sub clear_mounts_cache {
    undef $mounts_cache;
    undef $cached_mounts_file;
    Cpanel::CachedCommand::Utils::destroy( 'name' => $MOUNTS_CACHE, 'args' => [ get_mounts_file_path() ] );
    return 1;
}

sub get_mounts_without_jailed_filesystems {
    return \$mounts_cache if defined $mounts_cache;

    my $mounts_file_path = get_mounts_file_path();

    my $datastore_file = Cpanel::CachedCommand::Utils::get_datastore_filename( $MOUNTS_CACHE, $mounts_file_path );
    if ( _mount_cache_hit( $mounts_file_path, $datastore_file ) ) {
        if ( my $cache = Cpanel::LoadFile::loadfile($datastore_file) ) {
            $mounts_cache = $cache;
            return \$cache;
        }
    }

    my $dataref = Cpanel::LoadFile::load_r($mounts_file_path);
    $$dataref =~ s{^.+/(?:cagefs|virtfs)[/-].+$}{}mg;
    $$dataref =~ s{\n+}{\n}sg;
    substr( $$dataref, -1, 1, '' );

    require Cpanel::FileUtils::Write;
    try {
        Cpanel::FileUtils::Write::overwrite( $datastore_file, $$dataref, 0600 );
    }
    catch {
        my $err = $_;
        require Errno;
        if ( $! != Errno::EDQUOT() && eval { $err->get('error') } != Errno::EDQUOT() ) {
            local $@ = $err;
            die;    # Will re-throw $@
        }
    };

    $mounts_cache = $$dataref;

    return $dataref;
}

# Prefer /proc/self/mountstats as its faster
sub get_mount_stats_file_path {
    return -e $PROC_MOUNT_STATS_FILE ? $PROC_MOUNT_STATS_FILE : get_mounts_file_path();
}

sub get_mount_point_from_device {
    return ( scalar get_disk_mounts() )->{ $_[0] };
}

## returns hash (device => mount point) via '/proc/mounts' or 'bin/df'
sub get_disk_mounts {
    if ( keys %fsmap ) {
        return wantarray ? %fsmap : \%fsmap;
    }
    foreach my $device ( @{ get_disk_mounts_arrayref() } ) {
        $fsmap{ $device->{'filesystem'} } = $device->{'mount'} if ( !exists $fsmap{ $device->{'filesystem'} } || length $fsmap{ $device->{'filesystem'} } > length $device->{'mount'} );
    }
    return wantarray ? %fsmap : \%fsmap;
}

sub get_disk_mounts_arrayref {
    my ( $use_df, $include_virtfs ) = @_;
    my @mounts;

    my $mount_list_file = Cpanel::Filesys::Mounts::get_mounts_file_path();
    return _get_disk_mounts_arrayref_using_df() if $use_df || !Cpanel::StatCache::cachedmtime($mount_list_file);    # for legacy compat
    my $buffer = $include_virtfs ? Cpanel::LoadFile::load_r($mount_list_file) : Cpanel::Filesys::Mounts::get_mounts_without_jailed_filesystems();

    # always prefer the highest level mount point (See case 54414)
    # remove duplicates, preserve last entry ( will remove rootfs at / )
    my ( $device, $mount_point, $fstype );
    my %seen;
    @mounts = reverse map {
        ( $device, $mount_point, $fstype ) = split( m{ }, $_ );
        $mount_point =~ s/\\([0-9]{3})/$mount_unescapes{$1}/g if index( $mount_point, '\\' ) > -1;
        ( $seen{$mount_point}++ || $EXCLUDE_MOUNTS{ substr( $mount_point, 0, index( $mount_point, '/', 1 ) ) } || $EXCLUDE_FS{$fstype} ) ?    #
          ()
          :                                                                                                                                   #
          { 'mount' => $mount_point, 'filesystem' => $device }                                                                                #
    } reverse split( m{\n}, $$buffer );

    if ( !@mounts ) {
        Cpanel::Debug::log_info("Unable to parse $mount_list_file. Defaulting to 'df -P -k -l' output.");
        return _get_disk_mounts_arrayref_using_df();
    }
    return \@mounts;
}

sub _get_disk_mounts_arrayref_using_df {
    ## case 33663: uses -P
    my @mounts;
    require Cpanel::CachedCommand;
    my @df      = split( /\n/, Cpanel::CachedCommand::cachedmcommand( '3600', '/bin/df', '-P', '-k', '-l' ) );
    my $addline = '';
    foreach my $line (@df) {
        if ( $line !~ m/\s+/ ) {
            $addline = $line;
            next;
        }
        elsif ( $addline || $line =~ m/^\// ) {
            $line    = $addline . ' ' . $line;
            $addline = '';
            if ( $line =~ m/^\s*(\/\S+)\s+\d+\s+\d+\s+\d+\s+\S+\s+(\S+)/ ) {
                my $device      = $1;
                my $mount_point = $2;
                next if ( $mount_point =~ m/\/virtfs\// || $mount_point =~ m/^\/(?:proc|dev|boot|sys)/ );

                # always prefer the highest level mount point (See case 54414)
                push @mounts, { 'mount' => $mount_point, 'filesystem' => $device };
            }
        }
    }
    return \@mounts;
}

sub _mount_cache_hit {
    my ( $mounts_file_path, $datastore_file ) = @_;
    my $datastore_mtime       = ( ( stat($datastore_file) )[9] || 0 );
    my $datastore_expire_time = ( time() - $MOUNTS_CACHE_TTL );
    return ( $datastore_mtime > $datastore_expire_time && $datastore_mtime > ( stat($FSTAB_FILE) )[9] ) ? 1 : 0;
}

1;
