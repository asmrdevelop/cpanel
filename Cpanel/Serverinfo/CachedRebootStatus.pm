package Cpanel::Serverinfo::CachedRebootStatus;

# cpanel - Cpanel/Serverinfo/CachedRebootStatus.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant {
    _EACCES             => 13,
    _ENOENT             => 2,
    _EEXIST             => 17,
    QUEUE_WAIT_TIME     => 5,          # Time to wait before starting the background update.
    UPDATE_TIMEOUT      => 15 * 60,    # Max update time; after this, locks will be broken.
    MIN_UPDATE_INTERVAL => 30 * 60,    # How long to wait before refreshing the cache.
};

# All files in /var/run are deleted on boot: http://refspecs.linuxfoundation.org/FHS_3.0/fhs/ch03s15.html
sub REBOOT_STATUS_CACHE_FILE { return '/var/run/system_needs_reboot.cache' }
sub REBOOT_STATUS_CACHE_LOCK { return '/var/run/system_needs_reboot.cache.lock' }

use Cpanel::Fcntl::Constants   ();
use Cpanel::JSON               ();
use Cpanel::LoadFile::ReadFast ();
use Cpanel::LoadModule         ();

#Returns 0 if no reboot is needed, 1 if it is, and undef if we can’t tell.
sub system_needs_reboot {
    my $mtime = 0;
    my $needs_reboot;

    if ( open my $fh, '<', REBOOT_STATUS_CACHE_FILE() ) {
        $mtime = ( stat $fh )[9];
        my $json = '';
        Cpanel::LoadFile::ReadFast::read_all_fast( $fh, $json );
        close $fh;

        $needs_reboot = Cpanel::JSON::Load($json) if length $json;
    }
    elsif ( $! == _EACCES ) {
        return undef;    #Can’t open the file, so we can’t tell.
    }
    elsif ( $! != _ENOENT ) {
        my $path = REBOOT_STATUS_CACHE_FILE();
        die "open($path): $!";
    }

    # If we're root and the cache is over 30 min old, refresh it in an async
    # process.
    if ( !$> && time - $mtime > MIN_UPDATE_INTERVAL ) {

        # Touch the file so no other processes enter this block.  This is not a
        # critical section, as other processes can enter this block at the same
        # time; but, it prevents future processes from going down this path.
        require Cpanel::FileUtils::TouchFile;
        Cpanel::FileUtils::TouchFile::touchfile( REBOOT_STATUS_CACHE_FILE() );

        # If a task is queued more than once, but has not yet been run, then
        # the task queue collapses the two entries into one.  So, by waiting a
        # few seconds, we give the queue time to collapse before we fire off
        # the job, effectively preventing multiple simultaneous runs.
        Cpanel::LoadModule::load_perl_module('Cpanel::ServerTasks');
        Cpanel::ServerTasks::schedule_task( ['SystemTasks'], QUEUE_WAIT_TIME, "recache_system_reboot_data" );
    }

    return $needs_reboot;
}

### All functions below this line are used by Cpanel::ServerTasks::SystemTasks.

sub _update_cache_file {

    # We write all the contents to a lock file and then rename it for atomic
    # changes to the file.  Instead of using a temp file, we create a new file
    # at a known path with O_EXCL.  This lets us avoid wasting CPU time by
    # ensuring only one process attempts to do the update.  However, not using
    # a temp file means we need to support lock breaking.
    my $lock_file = REBOOT_STATUS_CACHE_LOCK();
    sysopen my $fh, $lock_file, $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL, 0600 or do {
        if ( $! == _EEXIST ) {

            # If the lock is older than the timeout, break it to avoid starvation.
            __break_stale_lockfile_if_necessary( $lock_file, UPDATE_TIMEOUT );
            return;    # Regardless, we abort; the next run can re-try.
        }

        # An unexpected error occurred; percolate it up.
        Cpanel::LoadModule::load_perl_module('Cpanel::Exception');
        die Cpanel::Exception::create( 'IO::FileCreateError', [ error => $!, path => $lock_file, permissions => 0600 ] );
    };

    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');
    Cpanel::LoadModule::load_perl_module('Whostmgr::API::1::ApplicationVersions');

    my $data = Whostmgr::API::1::ApplicationVersions::system_needs_reboot( { 'no_cache_update' => 1 }, {} );

    Cpanel::JSON::DumpFile( $fh, $data );
    close $fh;

    Cpanel::Autodie::rename( $lock_file, REBOOT_STATUS_CACHE_FILE() );

    return;
}

sub _abort_cache_file_update {
    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');
    Cpanel::Autodie::unlink( REBOOT_STATUS_CACHE_LOCK() );
    return;
}

sub __break_stale_lockfile_if_necessary {
    my ( $file, $timeout ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeFile');

    # If we can't acquire a lock, we assume another process has done so and
    # that we don't need to do anything, as it will be taken care of.  This
    # lock is to avoid basic TOCTOU races when unlinking a stale file, but is
    # subject to the limitations of Cpanel::SafeFile.
    my $lock = Cpanel::SafeFile::safelock($file) || return;

    # If the file still exists and is older than the timeout, we delete it.
    my $mtime = ( stat $file )[9];
    Cpanel::Autodie::unlink($file) if $mtime && time - $mtime > $timeout;
    Cpanel::SafeFile::safeunlock($lock);

    return 1;
}

1;
__END__

=head1 NAME

Cpanel::Serverinfo::CachedRebootStatus - Provides cached data for system_needs_reboot

=head1 SYNOPSIS

    use Cpanel::Serverinfo::CachedRebootStatus ();

    my $cached = Cpanel::Serverinfo::CachedRebootStatus::system_needs_reboot();

    # For live data, in the same format.
    my $live = Whostmgr::API::1::ApplicationVersions::system_needs_reboot( {}, {} );

=head1 DESCRIPTION

This module caches the output of the WHM API v1 system_needs_reboot API call,
and returns the cached information for significant speed savings.  The cache
returns immediately, whether or not there is information available.  If there
is no cached information available or if it is expired (i.e. more than 30 min
old), a background process is queued to update the cache with the latest
information.  Calls that occur after this background process completes will
have the updated data.

On system boot, the cache is cleared and will need at least one call to
C<Cpanel::Serverinfo::CachedRebootStatus::system_needs_reboot> to populate the
cache.  Thus, the first call after boot will always return that no reboot is
required, regardless of reality.

The cache is stored on the filesystem and is shared among all processes.

=head2 Cache Updates

This module relies on the C<Cpanel::TaskProcessors::SystemTasks> task queue
processor to perform the update in the background, however, that processor
simply calls functions provided by this module.

=head1 FUNCTIONS

=head2 C<system_needs_reboot()>

Returns a cached value of C<system_needs_reboot>; see
L<Whostmgr::API::1::ApplicationVersions/system_needs_reboot>.

B<Returns:> C<undef>, if the cache is not yet populated; the cached return
value of WHM's system_needs_reboot API call, otherwise.

=cut
