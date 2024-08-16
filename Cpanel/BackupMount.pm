package Cpanel::BackupMount;

# cpanel - Cpanel/BackupMount.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use IO::Handle                   ();
use Cpanel::SafeFile             ();
use Cpanel::SafeRun::Errors      ();
use Cpanel::Binaries             ();
use Cpanel::Logger               ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::ServerTasks          ();
use Cpanel::Filesys::Mounts      ();

our $VERBOSE = 0;

my ( $mount_bin, $umount_bin, $losetup_bin, $mountkeyword );

my $logger ||= Cpanel::Logger->new();

sub _init {
    if ( !$mountkeyword ) {
        $mountkeyword = 'remount';
    }

    $mount_bin  ||= Cpanel::Binaries::path('mount');
    $umount_bin ||= Cpanel::Binaries::path('umount');

    if ( !-x $mount_bin ) {
        $logger->panic('Unable to locate suitable mount binary');
    }

    if ( !-x $umount_bin ) {
        $logger->panic('Unable to locate suitable umount binary');
    }

    $losetup_bin ||= Cpanel::Binaries::path('losetup');

    return 1;
}

# returns 1 if lock obtained
sub _get_mount_lock ( $basemount, $mountkey, $mount_lock_ttl ) {

    Cpanel::FileUtils::TouchFile::touchfile( $basemount . '/.backupmount_locks' ) if !-e $basemount . '/.backupmount_locks';

    my $lock_fh = IO::Handle->new();
    if ( my $lock = Cpanel::SafeFile::safeopen( $lock_fh, '+<', $basemount . '/.backupmount_locks' ) ) {
        {
            local $/;

            # We use (split(/=/, $_))[0,1] here to ensure null elements do not break the hash
            my %LOCKS = map { ( split( /=/, $_ ) )[ 0, 1 ] } split( /\n/, readline($lock_fh) );
            delete $LOCKS{''};
            $LOCKS{$mountkey} = ( $mount_lock_ttl + time() );
            seek( $lock_fh, 0, 0 );
            print {$lock_fh} join( "\n", map { "$_=$LOCKS{$_}" } sort keys %LOCKS ) . "\n";    # Sorted for debugging reasons
            Cpanel::SafeFile::safeclose( $lock_fh, $lock );
        }

        Cpanel::ServerTasks::schedule_task( ['BackupMountTasks'], ( $mount_lock_ttl + 1 ), 'release_mount_lock ' . $basemount );

        return 1;
    }

    return;
}

# returns 1 if ALL locks are released or expired
sub release_mount_lock {
    my $basemount = shift;
    my $mountkey  = shift || '';

    my $lock_fh = IO::Handle->new();
    if ( my $lock = Cpanel::SafeFile::safeopen( $lock_fh, '+<', $basemount . '/.backupmount_locks' ) ) {
        local $/;

        # We use (split(/=/, $_))[0,1] here do ensure null elements do not break the hash
        my %LOCKS    = map { ( split( /=/, $_ ) )[ 0, 1 ] } split( /\n/, readline($lock_fh) );
        my $now      = time();
        my $tomorrow = $now + 86400;
        delete @LOCKS{ '', $mountkey, ( grep { $LOCKS{$_} < $now || $LOCKS{$_} > $tomorrow } keys %LOCKS ) };
        seek( $lock_fh, 0, 0 );
        print {$lock_fh} join( "\n", map { "$_=$LOCKS{$_}" } sort keys %LOCKS ) . "\n";    # Sorted for debugging reasons
        truncate( $lock_fh, tell($lock_fh) );
        Cpanel::SafeFile::safeclose( $lock_fh, $lock );
        return 1 if scalar keys %LOCKS == 0;
    }

    return;
}

#NOTE: Consider Cpanel::BackupMount::Object instead, which uses
#Perl's DESTROY garbage collection to call this automatically.
sub unmount_backup_disk ( $basemount, $mountkey ) {

    _init();

    my $can_umount = 1;
    my $loopdev;
    my ( $ismounted, $mountline ) = backup_disk_is_mounted($basemount);
    if ($ismounted) {
        if ( $mountline =~ /\([^)]*loop=([^,)\s]+)\)/ ) {
            $loopdev = $1;
        }
        $can_umount = release_mount_lock( $basemount, $mountkey );
    }

    if ($can_umount) {
        return if !_run_hook_script( '/usr/local/cpanel/scripts/pre_cpbackup_unmount', $basemount );
        if ( -x '/usr/local/cpanel/scripts/cpbackup_unmount' ) {
            return if !_run_hook_script( '/usr/local/cpanel/scripts/cpbackup_unmount', $basemount );
        }
        else {
            print "[backupmount] Shutting down mount\n"                                                               if $VERBOSE;
            print "[backupmount] running: " . join( ' ', $mount_bin, '-o', $mountkeyword . ',ro', $basemount ) . "\n" if $VERBOSE;
            Cpanel::Filesys::Mounts::clear_mounts_cache();
            system( $mount_bin, '-o', $mountkeyword . ',ro', $basemount );
            print "[backupmount] running: " . join( ' ', $umount_bin, $basemount ) . "\n" if $VERBOSE;
            system( $umount_bin, $basemount );
            if ( -x $losetup_bin && $loopdev ) {
                print "[backupmount] running: " . join( ' ', $losetup_bin, '-d', $loopdev ) . "\n" if $VERBOSE;
                system( $losetup_bin, '-d', $loopdev );
                undef $loopdev;
            }
            return 1;
        }
        _run_hook_script( '/usr/local/cpanel/scripts/post_cpbackup_unmount', $basemount );
    }
    else {
        print "[backupmount] Cannot umount: $basemount.  This mountpoint is still in use and has an active lock\n";
    }
    return;
}

#NOTE: Consider Cpanel::BackupMount::Object instead, which uses
#Perl's DESTROY garbage collection to ensure this will be unmounted.
sub mount_backup_disk {
    my $basemount      = shift;
    my $mountkey       = shift;
    my $mount_lock_ttl = shift || 86400;
    _init();

    print "[backupmount] Setting up mount\n" if $VERBOSE;
    return                                   if !_run_hook_script( '/usr/local/cpanel/scripts/pre_cpbackup_mount', $basemount );

    if ( -x '/usr/local/cpanel/scripts/cpbackup_mount' ) {
        return if !_run_hook_script( '/usr/local/cpanel/scripts/cpbackup_mount', $basemount );
    }
    else {
        Cpanel::Filesys::Mounts::clear_mounts_cache();
        print "[backupmount] running: " . join( ' ', $mount_bin, $basemount ) . "\n" if $VERBOSE;
        system( $mount_bin, $basemount );
        print "[backupmount] running: " . join( ' ', $mount_bin, '-o', $mountkeyword . ',rw', $basemount ) . "\n" if $VERBOSE;
        system( $mount_bin, '-o', $mountkeyword . ',rw', $basemount );
    }

    _run_hook_script( '/usr/local/cpanel/scripts/post_cpbackup_mount', $basemount );

    #TODO: This doesn't seem to indicate success or failure to the caller..?
    _get_mount_lock( $basemount, $mountkey, $mount_lock_ttl );

    return 1;
}

sub backup_disk_is_mounted ($basemount) {

    _init();
    my $ismounted = 0;
    my @MOUNT     = Cpanel::SafeRun::Errors::saferunnoerror($mount_bin);
    my $mountline;
    foreach (@MOUNT) {
        chomp();
        my $point;
        ( undef, undef, $point, undef ) = split( / /, $_ );
        if ( $point eq $basemount ) {
            $mountline = $_;
            $ismounted = 1;
            last;
        }
    }
    return wantarray ? ( $ismounted, $mountline ) : $ismounted;
}

sub _run_hook_script ( $script, @args ) {

    return 1 if !-x $script;
    print "[backupmount] Running: $script\n";
    system $script, @args;
    my $exit_code = ( $? >> 8 );
    if ( $exit_code != 0 ) {
        print "[backupmount] $script exited with non-zero status: $exit_code\n";
        return;
    }
    return 1;
}

1;
