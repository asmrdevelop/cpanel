package Cpanel::SafeFile;

# cpanel - Cpanel/SafeFile.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

################################################################################
#
#   PLEASE DO NOT USE THIS MODULE IN NEW CODE UNLESS YOU USE
#   Cpanel::SafeFile::Replace.
#
#   Please use Cpanel::Transaction::* instead as it does all the
#   magic for you.
#
################################################################################

##
## MEMORY REQUIREMENTS: this module is loaded into libexec/queueprocd
## Do not add new dependencies, however small.
##

use Cpanel::TimeHiRes        ();
use Cpanel::Fcntl::Constants ();
use Cpanel::SafeFileLock     ();
use Cpanel::FHUtils::Tiny    ();

use constant {
    _EWOULDBLOCK => 11,
    _EACCES      => 13,
    _EDQUOT      => 122,
    _ENOENT      => 2,
    _EINTR       => 4,
    _EEXIST      => 17,
    _ENOSPC      => 28,
    _EPERM       => 1,

    MAX_LOCK_CREATE_ATTEMPTS => 90,

    NO_PERM_TO_WRITE_TO_DOTLOCK_DIR => -1,

    INOTIFY_FILE_DISAPPEARED => 2,

    CREATE_FCNTL_VALUE => ( $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_EXCL | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_NONBLOCK ),
    UNLOCK_FCNTL_VALUE => $Cpanel::Fcntl::Constants::LOCK_UN,

    #NOTE: We used to write lock files 0600, which made it impossible for
    #unprivileged callers to inspect the lock if another user owns the
    #lock. Now we write the lock file 0644, which does expose $0 but also
    #allows us to use file handles for more reliable locking.
    LOCK_FILE_PERMS => 0644,

    # After this time we assume that we have a deadlock condition and we can overwrite the lock
    # This can be overwritten with local $Cpanel::SafeFile::LOCK_WAIT_TIME = $lock_waittime;
    # before calling safeopen or safesysopen
    DEFAULT_LOCK_WAIT_TIME => 196,

    # DEFAULT_LOCK_WAIT_TIME must always be at least 15s longer that
    # $HTTP_RESTART_TIMEOUT in Cpanel::HttpUtils::ApRestart to avoid
    # the lock geting busted during an apache restart
    MAX_LOCK_WAIT_TIME => 400,

    # Maximum lengh for the lockfile before we have to transform the name
    # into a hash.  We must do this because the temp lockfile adds extra
    # characters to the end and will exceed the maximum allowed file length.
    MAX_LOCK_FILE_LENGTH => 225,
};

$Cpanel::SafeFile::VERSION = '5.0';

my $OVERWRITE_FCNTL_VALUE;
my $verbose = 0;    # initialized in safelock

# This value can be overwritten externally (see AcctLock and Cpanel::Transaction::File::Base)
our $LOCK_WAIT_TIME;    #allow lock wait time to be overwritten

# -- internals
my $OPEN_LOCKS = 0;

our $TIME_BETWEEN_DOTLOCK_CHECKS = 0.3;
our $TIME_BETWEEN_FLOCK_CHECKS   = 0.05;
our $MAX_FLOCK_WAIT              = 60;     # allowed to be overwritten in tests

# There are still parts of the codebase that rely
# only on flock() and do not create a dot lock file
#
# For example: /etc/valiases and /etc/vfilters
# When opening these with safelock we tell the system
# its ok to fail creating the dotlock file by setting
# local $_SKIP_DOTLOCK_WHEN_NO_PERMS = 1;
# before calling safeopen, which there is a convenience function for you
# so please use safeopen_skip_dotlock_if_not_root for this purpose
our $_SKIP_DOTLOCK_WHEN_NO_PERMS = 0;

# If set we will not warn when opening the file fails
our $_SKIP_WARN_ON_OPEN_FAIL = 0;

# -- end internals

my $DOUBLE_LOCK_DETECTED = 4096;

sub safeopen {    #fh, open()-style mode, path
    my ( $mode, $file ) = _get_open_args( @_[ 1 .. $#_ ] );

    # parameter order: filehandle, open mode, filepath
    my $open_method_coderef = sub {
        my $ret = open( $_[0], $_[1], $_[2] ) || do {
            _log_warn("open($_[1], $_[2]): $!");
            return undef;
        };
        return $ret;
    };

    return _safe_open( $_[0], $mode, $file, $open_method_coderef, 'safeopen' );
}

sub safesysopen_no_warn_on_fail {
    local $_SKIP_WARN_ON_OPEN_FAIL = 1;

    return safesysopen(@_);
}

sub safesysopen_skip_dotlock_if_not_root {
    local $_SKIP_DOTLOCK_WHEN_NO_PERMS = $> == 0 ? 0 : 1;

    return safesysopen(@_);
}

sub safeopen_skip_dotlock_if_not_root {
    local $_SKIP_DOTLOCK_WHEN_NO_PERMS = $> == 0 ? 0 : 1;

    return safeopen(@_);
}

sub safelock_skip_dotlock_if_not_root {
    local $_SKIP_DOTLOCK_WHEN_NO_PERMS = $> == 0 ? 0 : 1;

    return safelock(@_);
}

#Reopen a filehandle--assumedly in a different mode, but not necessarily.
#This establishes an flock() after open(); assuming that
#there is also cPanel lock file in play, this can ensure race safety.
#
#NOTE: It is possible to use this with "regular", non-locked filehandles.
#That's probably not useful, though...?
#
sub safereopen {    ##no critic qw(RequireArgUnpacking)
    my $fh = shift;

    # If the file handle isn't open, then it's not a re-open
    if ( !$fh ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Undefined filehandle not allowed!");
    }
    elsif ( !fileno $fh ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("Closed filehandle ($fh) not allowed!");
    }

    my ( $mode, $file ) = _get_open_args(@_);

    # parameter order: filehandle, open mode, filepath
    my $open_method_coderef = sub {
        return open( $_[0], $_[1], $_[2] ) || do {
            _log_warn("open($_[1], $_[2]): $!");
            return undef;
        };
    };

    return _safe_re_open( $fh, $mode, $file, $open_method_coderef, 'safereopen' );
}

#$open_mode is numeric
#$custom_perms are actual filesystem perms, not a mask the way Perl does it.
#NOTE: "perms" are actual filesystem perms, not a mask the way Perl does it.
sub safesysopen {    ##no critic qw(RequireArgUnpacking)
                     # $_[0]: fh
    my ( $file, $open_mode, $custom_perms ) = ( @_[ 1 .. 3 ] );

    my ( $sysopen_perms, $original_umask );

    $open_mode = _sanitize_open_mode($open_mode);

    # parameter order: filehandle, open mode, filepath
    my $open_method_coderef = sub {
        return sysopen( $_[0], $_[2], $_[1], $sysopen_perms ) || do {
            _log_warn("open($_[2], $_[1], $sysopen_perms): $!") unless $_SKIP_WARN_ON_OPEN_FAIL;
            return undef;
        };
    };

    if ( defined $custom_perms ) {
        $custom_perms &= 0777;
        $original_umask = umask( $custom_perms ^ 07777 );
        $sysopen_perms  = $custom_perms;
    }
    else {
        $sysopen_perms = 0666;
    }

    my $lock_ref;

    local $@;
    my $ok = eval {
        $lock_ref = _safe_open( $_[0], $open_mode, $file, $open_method_coderef, 'safesysopen' );
        1;
    };

    if ( defined $custom_perms ) {
        umask($original_umask);
    }

    die if !$ok;

    return $lock_ref;
}

sub safeclose {
    my ( $fh, $lockref, $do_something_before_releasing_lock ) = @_;

    if ( $do_something_before_releasing_lock && ref $do_something_before_releasing_lock eq 'CODE' ) {
        $do_something_before_releasing_lock->();
    }

    my $success = 1;
    if ( $fh && defined fileno $fh ) {

        # We now do LOCK_UN since closing the file handle
        # does not always unblock the lock right away
        flock( $fh, UNLOCK_FCNTL_VALUE ) or _log_warn( "flock(LOCK_UN) on “" . $lockref->get_path() . "” failed with error: $!" );    # LOCK_UN
        $success = close $fh;
    }

    # We used to remove the .lock file before
    # we released the flock, however since we
    # create the .lock first this could cause
    # the .lock to be aquired while the file
    # was still flock()ed or worse on NFS.
    # This was changed in CPANEL-4393
    my $safe_unlock = safeunlock($lockref);

    $OPEN_LOCKS-- if ( $safe_unlock && $success );

    return ( $safe_unlock && $success );
}

# Provides an advisory lock for a given file by creating a lock file on disk.
#
# If a lock file exists but the process (identified by PID) that created it
# is no longer running, then the stale lock will automatically be overriden.
#
# This function prevents deadlock by breaking the lock files after an amount
# of time (between 60 & 350 seconds, inclusive -- can be overriden with the
# $LOCK_WAIT_TIME global) which will be referred to as the "wait time".
# However, this feature can lead to race conditions (see example below).
#
# This lock works best when the expected contention is very low; that is,
# when we expect that no more than one other process MAY contend of the file
# at any given time and we expect neither process to need the lock for more
# than half the wait time.  Having more processes, or critical sections that
# are nearly as long - or longer - than the wait time may result in multiple
# processes "getting" (really, "taking") the lock, which may cause subsequent
# race conditions.
#
# For example, the following sequence can cause a race condition:
#   process 0 locks file
#   sleep 1
#   process 1, 2, & 3 attempt to lock file
#   [time passes]
#   process 0 unlocks file, process 2 locks it
#   [time passes]
#   process 1 & 3 both independently break the lock (at the same time) because:
#     - Wait time has occurred since process 1 & 3 initially tried to lock
#     - Wait time was not reset when process 2 got the lock
#     - Wait time for process 3 will not be reset when 1 gets the lock (or vice-versa)
#
# Note, this lock file should be unlocked with safeunlock(), it is not cleaned
# up automatically on exit.  It is the lock breaking mechanism that clears out
# stale locks.
#
# Params:
#   $file   The file to lock (a separate lock file will be created).
# Returns:
#   On success, returns a Cpanel::SafeFileLock instance (a brief view of the code also shows that 1 may be returned)
#   On failure, returns undef
sub safelock {
    my ($file) = @_;

    my $lock_obj = _safelock($file);

    # _safelock is called from the safeopen
    # calls in this module.  If the directory
    # or lock file is not writable, it returns 1 so
    # that the open proceeds and falls back to flock
    # If we call safelock directly and we do not
    # get a Cpanel::SafeFileLock object back from
    # _safelock, we should consider this a failure
    # and return nothing.
    #

    # return undef if its not a Cpanel::SafeFileLock instance
    # as it may be a
    #   double lock
    #   permission denied
    #   or other failure
    return if !ref $lock_obj;

    return $lock_obj;
}

#
#- On success, returns a Cpanel::SafeFileLock instance
#
#- On double lock, returns 0
#
#- On permission denied, returns 1 because _safe_open will
#   still do the flock() even if it cannot write the .lock
#
#- On failure, returns undef
#
#NB: Tests call this directly, but please don’t call it from
#production code.
#
sub _safelock {
    my ($file) = @_;
    if ( !$file || $file =~ tr/\0// ) {
        _log_warn('safelock: Invalid arguments');
        return;
    }
    $verbose ||= ( _verbose_flag_file_exists() ? 1 : -1 );

    my $lockfile      = _calculate_lockfile($file);
    my $safefile_lock = Cpanel::SafeFileLock->new_before_lock( $lockfile, $file );
    my ( $lock_status, $lock_fh, $attempts, $last_err );

    {
        local $@;

        # Try multiple times, _lock_wait will bail out if it
        # encounters a race condition where another
        # process obtains a lock during our attempt
        # to obtain one, and we will have to try again.
        while ( ++$attempts < MAX_LOCK_CREATE_ATTEMPTS ) {

            ( $lock_status, $lock_fh ) = _lock_wait( $file, $safefile_lock, $lockfile );

            last if $lock_status;

            $last_err = $!;

            if ( $lock_fh && $lock_fh == $DOUBLE_LOCK_DETECTED ) {
                return 0;
            }
        }

    }

    if ( $lock_fh == 1 ) {
        return 1;
    }
    elsif ( $lock_status && $lock_fh ) {
        return $safefile_lock;
    }

    _log_warn( 'safelock: waited for lock (' . $lockfile . ') ' . $attempts . ' times' );
    require Cpanel::Exception;
    die Cpanel::Exception::create( 'IO::FileCreateError', [ 'path' => $lockfile, 'error' => $last_err ] );
}

# Here we write the temporary dotlock file with the details about the lock.
# _lock_wait will be responsible for moving into place (obtaining the lock).
#
# By writing the temporary file before moving it into place we ensure that
# the details about the lock are always in the file and when another process
# comes around to read the details about the lock to check for a stale lock
# that they will never find an empty lock file.
#
# Returns:
# ( NO_PERM_TO_WRITE_TO_DOTLOCK_DIR, "error message" ) - This means that the directory wasn't writable so the lockfile couldn't be created. This is
# ( 0, "error message" )  - This means that the function failed in general, this will trigger a retry on creating the lock
sub _write_temp_lock_file {
    my ($lockfile) = @_;

    #Keep this module super-light by using custom temp file naming
    #logic rather than what’s in Cpanel::Rand. In this case, it’s
    #the original filename, then the hex representation of a random
    #number, epoch, and PID, all joined with “-”. Since we want the
    #higher entropy to come first, we reverse the PID and epoch.
    my $temp_file = sprintf(
        '%s-%x-%x-%x',
        $lockfile,
        substr( rand, 2 ),
        scalar( reverse time ),
        scalar( reverse $$ ),
    );

    my ( $ok, $fh_or_err ) = _create_lockfile($temp_file);
    if ( !$ok ) {

        # EDQUOT and ENOSPC prompt an error because we’re out of disk space.
        #
        # We could try again on EEXIST, but if that happens then there’s
        # probably an error in our logic since that means we got the same
        # rand() value in the same second and in the same PID.
        #
        # For now the only “special case” is EPERM or EACCES.

        if ( $fh_or_err == _EPERM() || $fh_or_err == _EACCES() ) {

            local $!;

            my $lock_dir = _getdir($lockfile);
            if ( !-w $lock_dir ) {

                # Ideally, if we can't write to the lock file or directory,
                # we should not be locking the file.  We should be warning
                # about this since this generally indicates a bug or design
                # flaw in our codebase.
                #
                #

                if ($_SKIP_DOTLOCK_WHEN_NO_PERMS) {    # A hack to allow /etc/valiases to still be flock()ed until we can refactor
                    return ( NO_PERM_TO_WRITE_TO_DOTLOCK_DIR, $fh_or_err );
                }
                else {
                    _log_warn("safelock: Failed to create a lockfile '$temp_file' in the directory '$lock_dir' that isn't writable: $fh_or_err");
                }
            }
        }

        return ( 0, $fh_or_err );
    }

    # Cpanel::SafeFileLock::write_lock_contents dies
    # on failure
    #
    Cpanel::SafeFileLock::write_lock_contents( $fh_or_err, $temp_file );

    return ( $temp_file, $fh_or_err );
}

#overridden in tests
sub _try_to_install_lockfile {
    my ( $temp_file, $lockfile ) = @_;

    link( $temp_file => $lockfile ) or do {
        return 0 if $! == _EEXIST;

        require Cpanel::Exception;

        #This can fail in a bunch of interesting ways, but they’re
        #all outlandish enough that it makes sense to die() on any of them.
        #(e.g., EMLINK, ENOSPC, etc. - cf. man 2 link)
        die Cpanel::Exception::create( 'IO::LinkError', [ oldpath => $temp_file, newpath => $lockfile, error => $! ] );
    };

    return 1;
}

sub safeunlock {
    my $lockref = shift;

    if ( !$lockref ) {
        _log_warn('safeunlock: Invalid arguments');
        return;
    }
    elsif ( !ref $lockref ) {
        return 1 if $lockref eq '1';    # No lock file created so just succeed
        $lockref = Cpanel::SafeFileLock->new( $lockref, undef, undef );
        if ( !$lockref ) {
            _log_warn("safeunlock: failed to generate a Cpanel::SafeFileLock object from a path");
            return;
        }
    }
    my ( $lock_path, $fh, $lock_inode, $lock_mtime ) = $lockref->get_path_fh_inode_mtime();

    # Note: We do this before the fileno check because we want to
    # do an if/elsif/elsif block since perl can optimize it. Its rare
    # that we would ever lose the lock so saving the lstat on lost lock
    # isn't likely to ever happen.
    #
    #We can’t use the SafeFileLock object’s lstat_ar() method here because
    #that method prefers to stat() the filehandle rather than the path.
    my ( $filesys_lock_ino, $filesys_lock_mtime ) = ( lstat $lock_path )[ 1, 9 ];

    # if lock is already closed, this is a success
    if ( $fh && !defined fileno($fh) ) {

        return 1;
    }
    elsif ( !$filesys_lock_mtime ) {
        _log_warn( 'Lock on ' . $lockref->get_path_to_file_being_locked() . ' lost!' );
        $lockref->close();
        return;    # return false on false
    }

    # If the fh we have open is the same inode we are good.
    # NB: Comparing inodes works here because the filehandle is still open.
    elsif ( $lock_inode && ( $lock_inode == $filesys_lock_ino ) && $lock_path && ( $lock_mtime == $filesys_lock_mtime ) ) {
        unlink $lock_path or do {
            _log_warn("Could not unlink lock file “$lock_path” as ($>/$)): $!\n");
            $lockref->close();
            return;    # return false on false
        };
        return $lockref->close();
    }

    $lockref->close();
    my ( $lock_pid, $lock_name, $lock_obj ) = Cpanel::SafeFileLock::fetch_lock_contents_if_exists($lock_path);

    #If !$lock_pid, then the lock file has gone away suddenly,
    #which we don’t need to care about here.
    if ($lock_pid) {

        $lock_inode ||= 0;
        $lock_mtime ||= 0;

        # Should not be invalid because if a proc dies off via cpanel update it will always fail from this point on
        _log_warn("[$$] Attempt to unlock file that was locked by another process [LOCK_PATH]=[$lock_path] [LOCK_PID]=[$lock_pid] [LOCK_PROCESS]=[$lock_name] [LOCK_INODE]=[$filesys_lock_ino] [LOCK_MTIME]=[$filesys_lock_mtime] -- [NON_LOCK_PID]=[$$] [NON_LOCK_PROCESS]=[$0] [NON_LOCK_INODE]=[$lock_inode] [NON_LOCK_MTIME]=[$lock_mtime]");
    }
    return;
}

sub _safe_open {

    #$_[0] = fh
    my ( undef, $open_mode, $file, $open_method_coderef, $open_method ) = @_;

    if ( !defined $open_mode || !$open_method_coderef || !$file || $file =~ tr/\0// ) {
        _log_warn('_safe_open: Invalid arguments');
        return;
    }
    elsif ( defined $_[0] ) {
        my $fh_type = ref $_[0];
        if ( !Cpanel::FHUtils::Tiny::is_a( $_[0] ) ) {
            _log_warn("Invalid file handle type '$fh_type' provided for $open_method of '$file'");
            return;
        }
    }

    # _safelock behaves like safelock with a
    # subtle difference.
    #
    # If the directory or lock file is not writable and _SKIP_DOTLOCK_WHEN_NO_PERMS is set,
    # it returns 1 so that the open proceeds and falls
    # back to flock.
    #
    if ( my $lockref = _safelock($file) ) {
        if ( $open_method_coderef->( $_[0], $open_mode, $file ) ) {
            if ( my $err = _do_flock_or_return_exception( $_[0], $open_mode, $file ) ) {
                safeunlock($lockref);
                local $@ = $err;
                die;
            }

            $OPEN_LOCKS++;
            return $lockref;
        }
        else {

            # If the open failed, it's likely that we don't care about
            # an error from unlock, so we'll just throw away any errno
            # we get out of it.
            local $!;

            safeunlock($lockref);
            return;
        }
    }
    else {
        _log_warn("safeopen: could not acquire a lock for '$file': $!");
        return;
    }
}

#Calculate this only when needed . . .
my $_lock_ex_nb;
my $_lock_sh_nb;

#Return the exception rather than throw it so that _safe_open() can
#safeunlock() as needs be without having to try/catch or eval {}.
sub _do_flock_or_return_exception {
    my ( $fh, $open_mode, $path ) = @_;

    my $flock_start_time;

    my $lock_op =
      _is_write_open_mode($open_mode)
      ? ( $_lock_ex_nb //= $Cpanel::Fcntl::Constants::LOCK_EX | $Cpanel::Fcntl::Constants::LOCK_NB )
      : ( $_lock_sh_nb //= $Cpanel::Fcntl::Constants::LOCK_SH | $Cpanel::Fcntl::Constants::LOCK_NB );

    local $!;
    my $flock_err;

    # We only use Cpanel::TimeHiRes::time() if MAX_FLOCK_TIME
    # is not a whole number because Cpanel::TimeHiRes::time()
    # is much more expensive than time() and we currently only
    # use it in tests
    my $flock_max_wait_time_is_whole_number = int($MAX_FLOCK_WAIT) == $MAX_FLOCK_WAIT;

    while ( !flock $fh, $lock_op ) {
        $flock_err = $!;

        # If we got a signal or if the file is currently locked,
        # then we’ll wait a bit then try again.
        if ( $flock_err == _EINTR || $flock_err == _EWOULDBLOCK ) {
            if ( !$flock_start_time ) {
                $flock_start_time = $flock_max_wait_time_is_whole_number ? time() : Cpanel::TimeHiRes::time();
                next;
            }

            #After $MAX_FLOCK_WAIT seconds we generate an exception
            if ( ( ( $flock_max_wait_time_is_whole_number ? time() : Cpanel::TimeHiRes::time() ) - $flock_start_time ) > $MAX_FLOCK_WAIT ) {
                require Cpanel::Exception;
                return _timeout_exception( $path, $MAX_FLOCK_WAIT );
            }
            else {
                Cpanel::TimeHiRes::sleep($TIME_BETWEEN_FLOCK_CHECKS);
            }
            next;
        }

        #We’re here because there was an flock error other than the
        #ones we tolerate: EINTR and EWOULDBLOCK. That’s not supposed
        #to happen, so it’s a failure.
        require Cpanel::Exception;
        return Cpanel::Exception::create( 'IO::FlockError', [ path => $path, error => $flock_err, operation => $lock_op ] );
    }

    return undef;
}

sub _safe_re_open {
    my ( $fh, $open_mode, $file, $open_method_coderef, $open_method ) = @_;

    if ( !defined $open_mode || !$open_method_coderef || !$file || $file =~ tr/\0// ) {
        _log_warn('_safe_re_open: Invalid arguments');
        return;
    }
    else {
        my $fh_type = ref $fh;
        if ( !Cpanel::FHUtils::Tiny::is_a($fh) ) {
            _log_warn("Invalid file handle type '$fh_type' provided for $open_method of '$file'");
            return;
        }
    }

    close $fh;
    if ( $open_method_coderef->( $fh, $open_mode, $file ) ) {
        if ( my $err = _do_flock_or_return_exception( $fh, $open_mode, $file ) ) {
            die $err;
        }

        return $fh;
    }
    return;
}

sub _log_warn {
    require Cpanel::Debug;
    goto &Cpanel::Debug::log_warn;
}

sub _get_open_args {
    my ( $mode, $file ) = @_;
    if ( !$file ) {
        ( $mode, $file ) = $mode =~ m/^([<>+|]+|)(.*)/;
        if ( $file && !$mode ) {
            $mode = '<';
        }
        elsif ( !$file ) {
            return;
        }
    }

    $mode =
        $mode eq '<'   ? '<'
      : $mode eq '>'   ? '>'
      : $mode eq '>>'  ? '>>'
      : $mode eq '+<'  ? '+<'
      : $mode eq '+>'  ? '+>'
      : $mode eq '+>>' ? '+>>'
      :                  return;

    return ( $mode, $file );
}

sub _sanitize_open_mode {
    my ($mode) = @_;

    return if $mode =~ m/[^0-9]/;

    my $safe_mode = ( $mode & $Cpanel::Fcntl::Constants::O_RDONLY );
    $safe_mode |= ( $mode & $Cpanel::Fcntl::Constants::O_WRONLY );
    $safe_mode |= ( $mode & $Cpanel::Fcntl::Constants::O_RDWR );
    $safe_mode |= ( $mode & $Cpanel::Fcntl::Constants::O_CREAT );
    $safe_mode |= ( $mode & $Cpanel::Fcntl::Constants::O_EXCL );
    $safe_mode |= ( $mode & $Cpanel::Fcntl::Constants::O_APPEND );
    $safe_mode |= ( $mode & $Cpanel::Fcntl::Constants::O_TRUNC );
    $safe_mode |= ( $mode & $Cpanel::Fcntl::Constants::O_NONBLOCK );

    return $safe_mode;
}

sub _calculate_lockfile {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $lockfile = $_[0] =~ tr{<>}{} ? ( ( $_[0] =~ /^[><]*(.*)/ )[0] . '.lock' ) : $_[0] . '.lock';

    # if the entire path is less than the maximum length, we're definitely good
    return $lockfile if ( length $lockfile <= MAX_LOCK_FILE_LENGTH );

    require File::Basename;
    my $lock_basename = File::Basename::basename($lockfile);

    # If the basename is of the required length, nothing more to do
    return $lockfile if ( length $lock_basename <= MAX_LOCK_FILE_LENGTH );

    # The lock file name is too long, turn it into a hash to guarantee proper length
    require Cpanel::Hash;
    my $hashed_lock_basename = Cpanel::Hash::get_fastest_hash($lock_basename) . ".lock";

    if ( $lockfile eq $lock_basename ) {
        return $hashed_lock_basename;
    }
    else {
        return File::Basename::dirname($lockfile) . '/' . $hashed_lock_basename;
    }
}

sub is_locked {
    my ($file) = @_;
    my $lockfile = _calculate_lockfile($file);
    my ( $lock_pid, $lock_name, $lock_obj ) = Cpanel::SafeFileLock::fetch_lock_contents_if_exists($lockfile);

    if ( _is_valid_pid($lock_pid) && _pid_is_alive($lock_pid) ) {
        return 1;
    }

    return 0;
}

sub _timeout_exception {
    my ( $path, $waited ) = @_;

    require Cpanel::Exception;
    return Cpanel::Exception::create( 'Timeout', 'The system failed to lock the file “[_1]” after [quant,_2,second,seconds].', [ $path, $waited ] );
}

sub _die_if_file_is_flocked_cuz_already_waited_a_while {
    my ( $file, $waited ) = @_;

    if ( _open_to_write( my $fh, $file ) ) {
        $_lock_ex_nb //= $Cpanel::Fcntl::Constants::LOCK_EX | $Cpanel::Fcntl::Constants::LOCK_NB;
        if ( flock( $fh, $_lock_ex_nb ) == 1 ) {

            #We succeeded in flock()ing the file, which means the lockfile
            #we’ve been waiting on is stale. We thus return() from this
            #function so that the calling function can clobber the
            #lockfile and establish an flock().
            #
            #It has been considered to hold onto the lock here and just create
            #the lock file, but as we normally create the lock file *then*
            #flock(), to hold onto the flock() here would be reversing the
            #expected order and potentially introducing exciting new race
            #safety problems.
            #
            #POSIX locks have a useful tool that just checks the lock state
            #and doesn’t actually apply a lock. *sigh*...

            #Should not fail …
            flock $fh, UNLOCK_FCNTL_VALUE or die "Failed to unlock “$file” after having just locked it: $!";
        }
        else {
            require Cpanel::Exception;

            if ( $! == _EWOULDBLOCK ) {
                die _timeout_exception( $file, $waited );
            }
            else {
                die Cpanel::Exception::create( 'IO::FlockError', [ path => $file, error => $!, operation => $_lock_ex_nb ] );
            }
        }
    }

    return;
}

sub _lock_wait {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $file, $safefile_lock, $lockfile ) = @_;

    my ( $temp_file, $fh ) = _write_temp_lock_file( $lockfile, $file );

    # Sometimes we expect this to fail due to permissions, such as when we're writing to /etc/valiases as the user
    if ( $temp_file eq NO_PERM_TO_WRITE_TO_DOTLOCK_DIR ) {
        return ( 1, 1 );
    }

    if ( !$temp_file ) {
        return ( 0, $fh );
    }

    # Set the fh, and put the unlinker in the safefile_lock object.
    # Putting the unlinker into the safefile_lock object effects a
    # deferral of the unlink of the temp file until after the lock
    # is released. Ordinarily we want temp files to be deleted right
    # away, but deferring the removal of this temp file reduces the
    # file locking overhead a bit. We want as few operations to take
    # place during the lock as possible.
    $safefile_lock->set_filehandle_and_unlinker_after_lock( $fh, Cpanel::SafeFile::_temp->new($temp_file) );

    # Ideal case: no lockfile exists
    return ( 1, $fh ) if _try_to_install_lockfile( $temp_file, $lockfile );

    #----------------------------------------------------------------------
    # Bleh. OK, $lockfile already exists.
    #Needs to revert to the original $0 when we write the lock file.
    local $0 = ( $verbose == 1 ) ? "$0 - waiting for lock on $file" : "$0 - waiting for lock";

    require Cpanel::SafeFile::LockInfoCache;
    require Cpanel::SafeFile::LockWatcher;

    my $watcher = Cpanel::SafeFile::LockWatcher->new($lockfile);

    my $waittime = _calculate_waittime_for_file($file);

    my ( $inotify_obj, $inotify_mask, $inotify_file_disappeared );

    my $start_time = time;
    my $waited     = 0;

    my $lockfile_cache = Cpanel::SafeFile::LockInfoCache->new($lockfile);

    my ( $inotify_inode, $inotify_mtime );

  LOCK_WAIT:
    while (1) {
        $waited = ( time() - $start_time );

        # Lock file is older than waittime, so just remove it.
        if ( $waited > $waittime ) {

            # Test the flock before we blow away the lock file:
            #
            # If the main file is flock()ed, then we’re done waiting
            # and we die() because we don’t want to clobber a lock
            # that is still in use.
            #
            # If the main file isn’t flock()ed, then we clobber the lockfile
            # *if* the inode matches. (But if the file’s not locked,
            # then should we have gotten here in the first place?)
            #
            # Any other condition/error prompts an exception.
            #
            _die_if_file_is_flocked_cuz_already_waited_a_while( $file, $waited );

            if ( defined $watcher->{'inode'} ) {
                require Cpanel::Debug;
                Cpanel::Debug::log_warn( sprintf "Replacing stale lock file: $lockfile. The kernel’s lock is gone, last modified %s seconds ago (mtime=$watcher->{'mtime'}), and waited over $waittime seconds.", time - $watcher->{'mtime'} );
            }

            # We need to overwrite and never unlink
            # as this creates a race condition where the
            # file could be missing for a very short period
            # of time and another locker will think the lock
            # is released
            return ( 1, $fh ) if _overwrite_lockfile_if_inode_mtime_matches( $temp_file, $lockfile, $watcher->{'inode'}, $watcher->{'mtime'} );

            #We should only get here if the inode exists but is *not* the
            #same inode that it most recently was. At this point we give
            #up and die().
            die _timeout_exception( $file, $waittime );
        }

        #If the lock file exists,
        #then check for double lock and staleness.
        #
        if ( $watcher->{'inode'} ) {
            my $lock_get = $lockfile_cache->get( @{$watcher}{ 'inode', 'mtime' } );

            if ( !$lock_get ) {

                # If $lock_get is falsy, then we know that the lock no longer
                # exists on disk with the same inode and mtime that the
                # watcher object last knew about. Thus, the watcher needs
                # to be reloaded.

                my $size_before_reload = $watcher->{'size'};
                $watcher->reload_from_disk();

                # CPANEL-16932: Handle empty lock files that should never exists since we rename them in place
                # Empty lock file are likely the result of a system crash or disk corruption
                if ( $size_before_reload == 0 && $watcher->{'size'} == 0 ) {
                    _log_warn("[$$] UID $> clobbering empty lock file “$lockfile” (UID $watcher->{'uid'}) written by “unknown” at $watcher->{'mtime'}");

                    # We need to overwrite and never unlink
                    # as this creates a race condition where the
                    # file could be missing for a very short period
                    # of time and another locker will think the lock
                    # is released

                    return ( 1, $fh ) if _overwrite_lockfile_if_inode_mtime_matches( $temp_file, $lockfile, $watcher->{'inode'}, $watcher->{'mtime'} );
                }

                next LOCK_WAIT;
            }

            my ( $lock_pid, $lock_name, $lock_obj ) = @$lock_get;

            #We know $lock_pid is valid because we already checked
            #!$lock_get above.
            if ( $lock_pid == $$ ) {
                $watcher->reload_from_disk();

                _log_warn("[$$] Double locking detected by self [LOCK_PATH]=[$lockfile] [LOCK_PID]=[$lock_pid] [LOCK_OBJ]=[$lock_obj] [LOCK_PROCESS]=[$lock_name] [ACTUAL_INODE]=[$watcher->{'inode'}] [ACTUAL_MTIME]=[$watcher->{'mtime'}]");
                return ( 0, $DOUBLE_LOCK_DETECTED );
            }
            elsif ( !_pid_is_alive($lock_pid) ) {

                my $time = time();

                # We need to overwrite and never unlink
                # as this creates a race condition where the
                # file could be missing for a very short period
                # of time and another locker will think the lock
                # is released
                if ( _overwrite_lockfile_if_inode_mtime_matches( $temp_file, $lockfile, $watcher->{'inode'}, $watcher->{'mtime'} ) ) {
                    _log_warn("[$$] TIME $time UID $> clobbered stale lock file “$lockfile” (NAME “$lock_name”, UID $watcher->{'uid'}) written by PID $lock_pid at $watcher->{'mtime'}");
                    return ( 1, $fh );
                }

                # We lost the race to clobber the dotlock file, which
                # means there is a new lock file, so we need to reload
                # from disk now so that the next loop is checking the new
                # lock file.
                $watcher->reload_from_disk();
                next LOCK_WAIT;
            }
            else {
                require Cpanel::Debug;
                Cpanel::Debug::log_info("[$$] Waiting for lock on $file held by $lock_name with pid $lock_pid") if $verbose == 1;
            }
        }

        return ( 1, $fh ) if _try_to_install_lockfile( $temp_file, $lockfile );

        #Well, it was worth a shot. Failure to install
        #means there is still a lock file there, though.

        #----------------------------------------------------------------------

        $watcher->reload_from_disk();

        if ( !$inotify_obj || !$inotify_inode || !$watcher->{'inode'} || $inotify_inode != $watcher->{'inode'} || $inotify_mtime != $watcher->{'mtime'} ) {

            # If we do not have an inotify_obj setup yet
            # lets make one here so we can break out of the
            # select() below as soon as the lock file is deleted
          INOTIFY: {
                ( $inotify_obj, $inotify_mask, $inotify_file_disappeared ) = _generate_inotify_for_lock_file($lockfile);

                #We need this even if $inotify_file_disappeared,
                #whether we restart LOCK_WAIT or check to be sure
                #the Inotify instance is on the correct inode.
                $watcher->reload_from_disk();

                if ( $inotify_file_disappeared || !$watcher->{'inode'} ) {

                    #If we get here, we can’t use whatever $inotify_obj
                    #might have been created.
                    undef $inotify_obj;

                    next LOCK_WAIT;
                }

                redo INOTIFY if $watcher->{'changed'};

                ( $inotify_inode, $inotify_mtime ) = @{$watcher}{ 'inode', 'mtime' };
            }
        }

        #Name as $inotify_mask to make it more obvious that
        #there is only one filehandle being select()ed.
        #
        #Since mtimes are granular to the second we sleep
        #slightly more than a quarter second.
        my $selected = _select( my $m = $inotify_mask, undef, undef, $TIME_BETWEEN_DOTLOCK_CHECKS );

        #Since this is a NONBLOCK Inotify instance, we need to make sure
        #there is data to read before we poll, or we'll get EAGAIN.
        if ( $selected == -1 ) {

            #If we get EINTR then we should just run the loop again.
            #Any other error is worth a die().
            die "select() error: $!" if $! != _EINTR();
        }
        elsif ($selected) {
            return ( 1, $fh ) if _try_to_install_lockfile( $temp_file, $lockfile );

            $watcher->reload_from_disk();

            #We know that there’s something to read on the inotify
            #instance because select() came back positive, and there was
            #only one handle being listened to. We don’t really care what
            #the event is; once this is done we’ll just try again to
            #install (i.e., link()) our lockfile into place.
            () = $inotify_obj->poll();
        }
    }

    return;
}

#mocked in tests
sub _select {
    return select( $_[0], $_[1], $_[2], $_[3] );
}

sub _generate_inotify_for_lock_file {
    my ($file) = @_;
    require Cpanel::Inotify;
    my $inotify_obj;
    my $rin = '';

    # No try::tiny here because this is in a tight loop
    #
    local $@;
    eval {
        $inotify_obj = Cpanel::Inotify->new( flags => ['NONBLOCK'] );

        #Most of the time the event that we will listen for is not a
        #“DELETE_SELF” event--in fact, we probably won’t ever get that
        #event because Cpanel::SafeFile::LockWatcher holds lock files open,
        #which prevents them from being fully deleted. What *does* happen
        #is that the unlink() on those files reduces their hard link count
        #to zero; that’s the event (ATTRIB) that will let us know we should
        #try to link our lock file into place. (We’ll leave DELETE_SELF in
        #for good measure.)
        $inotify_obj->add( $file, flags => [ 'ATTRIB', 'DELETE_SELF' ] );

        vec( $rin, $inotify_obj->fileno(), 1 ) = 1;
    };

    if ($@) {
        my $err = $@;

        # We used to not inform the caller that the file went
        # away, however that ended up leading to random stalls
        # in dnsadmin.  This is now handled correctly.
        #
        if ( eval { $err->isa('Cpanel::Exception::SystemCall') } ) {
            my $err = $err->get('error');
            if ( $err == _ENOENT ) {
                return ( undef, undef, INOTIFY_FILE_DISAPPEARED );
            }
            elsif ( $err != _EACCES ) {    # Don’t warn if EACCES
                local $@ = $err;
                warn;
            }
        }
        else {
            local $@ = $err;
            warn;
        }

        return;
    }

    return ( $inotify_obj, $rin, 0 );
}

sub _pid_is_alive {
    my ($pid) = @_;

    local $!;

    if ( kill( 0, $pid ) ) {
        return 1;
    }

    #kill() often fails when done as an unprivileged user
    elsif ( $! == _EPERM ) {
        return !!( stat "/proc/$pid" )[0];
    }

    return 0;
}

sub _calculate_waittime_for_file {
    my ($file) = @_;

    return $LOCK_WAIT_TIME if $LOCK_WAIT_TIME;

    # If the file doesn't exist, we still want a minimum of 60 seconds to
    # declare a lock file as old. The 0 value has a race condition where
    # the lock is created at the end of one second and we check at the
    # beginning of the next and delete a valid lock file.
    my $waittime = DEFAULT_LOCK_WAIT_TIME;

    if ( -e $file ) {
        $waittime = int( ( stat _ )[7] / 10000 );

        #waittime is always between DEFAULT_LOCK_WAIT_TIME
        #and MAX_LOCK_WAIT_TIME seconds, inclusive.
        $waittime = $waittime > MAX_LOCK_WAIT_TIME ? MAX_LOCK_WAIT_TIME : $waittime < DEFAULT_LOCK_WAIT_TIME ? DEFAULT_LOCK_WAIT_TIME : $waittime;
    }

    return $waittime;
}

sub _is_valid_pid {
    my $pid = shift;

    return 0 unless defined $pid;

    return $pid =~ tr{0-9}{}c ? 0 : 1;
}

sub _getdir {
    my @path = split( /\/+/, $_[0] );
    return join( '/', (@path)[ 0 .. ( $#path - 1 ) ] ) || '.';
}

sub _create_lockfile {
    my $lock_fh;

    # If O_CREAT and O_EXCL are set, open() shall fail if the file exists
    # Setting "O_CREAT|O_EXCL" prevents the file from being opened if it is a symbolic link. It does not protect against symbolic links in the file's path.
    return sysopen( $lock_fh, $_[0], CREATE_FCNTL_VALUE, LOCK_FILE_PERMS ) ? ( 1, $lock_fh ) : ( 0, $! );
}

#Give: filehandle (auto-vivified), path
sub _open_to_write {
    my $path = $_[1];

    $OVERWRITE_FCNTL_VALUE ||= ( $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_NONBLOCK | $Cpanel::Fcntl::Constants::O_APPEND | $Cpanel::Fcntl::Constants::O_NOFOLLOW );

    return sysopen( $_[0], $path, $OVERWRITE_FCNTL_VALUE, LOCK_FILE_PERMS );
}

sub _overwrite_lockfile_if_inode_mtime_matches {
    my ( $temp_file, $lockfile, $lockfile_inode, $lockfile_mtime ) = @_;

    my ( $inode, $mtime ) = ( stat $lockfile )[ 1, 9 ];

    if ( !$inode ) {
        die "stat($lockfile): $!" if $! != _ENOENT();
    }

    #XXX There’s a race condition here: $lockfile could be replaced in
    #this space between the stat() and the rename(), which would mean
    #we’d clobber a valid lock file. As of September 2017 that probably
    #means we’ll then sit and wait for the flock(); if that happens
    #within our flock() timeout then all is well; otherwise, the file
    #lock will only be flock(), not the lock file.

    if ( !$inode || ( $inode == $lockfile_inode && $mtime == $lockfile_mtime ) ) {
        rename( $temp_file, $lockfile ) or do {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'IO::RenameError', [ oldpath => $temp_file, newpath => $lockfile, error => $! ] );
        };

        return 1;
    }

    return 0;
}

sub _is_write_open_mode {
    my ($mode) = @_;

    if ( $mode =~ tr{0-9}{}c ) {
        if ( $mode && ( -1 != index( $mode, '>' ) || -1 != index( $mode, '+' ) ) ) {
            return 1;
        }
    }
    else {
        if ( $mode && ( ( $mode & $Cpanel::Fcntl::Constants::O_WRONLY ) || ( $mode & $Cpanel::Fcntl::Constants::O_RDWR ) ) ) {
            return 1;
        }
    }
    return 0;
}

sub _verbose_flag_file_exists {
    return -e '/var/cpanel/safefile_verbose';
}

#----------------------------------------------------------------------

package Cpanel::SafeFile::_temp;

=encoding utf-8

=head1 NAME

Cpanel::SafeFile::_temp - A class for representing a temporary dotlock file

=head1 SYNOPSIS

    my $temp_file = Cpanel::SafeFile::_temp->new($tempfile);

=head1 DESCRIPTION

When we create a dotlock file we write out a temporary file with the
details of the lock.  We get the exclusive (advisory) dotlock by moving
the file into place.  This class ensures that the temporary file
is removed in the event something goes wrong with obtaining the lock.

=cut

use constant _ENOENT => 2;

sub new { return bless [ $_[1], $_SKIP_DOTLOCK_WHEN_NO_PERMS, $$ ], $_[0]; }

sub DESTROY {
    local $!;

    # $_[0]->[0] = $tempfile
    # $_[0]->[1] = $_SKIP_DOTLOCK_WHEN_NO_PERMS when created
    # $_[0]->[2] = $original_pid
    unlink $_[0]->[0] or do {
        if ( !$_[0]->[1] && $! != _ENOENT && $_[0]->[2] == $$ ) {
            warn "unlink($_[0]->[0]): $!";
        }
    };

    return;
}

1;

__END__

=head1 All-In-One Safest

safe_readwrite( $path_to_file, $coderef );

where '$coderef' is:

sub {
    my ( $rw_fh, $safe_replace_content_coderef ) = @_;

    # do what you need with $rw_fh (+<)

    # return true with a string
    return 'Changed foo to bar' if $safe_replace_content_coderef->( $rw_fh,  \@new_contents ); # or less efficiently ( $rw_fh, @new_content )
    return;
}
