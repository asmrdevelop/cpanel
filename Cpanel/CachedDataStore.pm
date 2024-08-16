package Cpanel::CachedDataStore;

# cpanel - Cpanel/CachedDataStore.pm                 Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

##
##  ** DO NOT USE THIS MODULE IN NEW CODE IF IT CAN BE AVOIDED ***
##
##  This module is deprecated as its faster to just store the data using
##  Cpanel::Transaction::File::JSON
##

use Try::Tiny;

use Cpanel::AdminBin::Serializer ();
use Cpanel::LoadFile::ReadFast   ();
use Cpanel::Fcntl::Constants     ();
use Cpanel::Debug                ();
use Cpanel::Exception            ();

# When we use this module we almost always load multiple
# datastore so it makes sense to preload  Time::HiRes
use Time::HiRes ();

use constant {
    WRONLY_CREAT_EXCL => ( $Cpanel::Fcntl::Constants::O_WRONLY | $Cpanel::Fcntl::Constants::O_CREAT | $Cpanel::Fcntl::Constants::O_EXCL ),
    _EEXIST           => 17,
};

our $LOCK = 1;    #const
our $LAST_WRITE_CACHE_SERIALIZATION_ERROR;

# These are likely userdata files
# This value should match the maximum
# in Whostmgr::Accounts::Transfers::Domains + 1
our $MAX_CACHE_ELEMENTS = 32768 + 1;

my $MAX_CACHE_OBJECT_SIZE = 1024 * 512;    # do not cache objects larger than 512k

my $_iterations_since_last_cache_cleanup = 0;

my %DATASTORE_CACHE;

*_time  = *Time::HiRes::time;
*_utime = *Time::HiRes::utime;
*_stat  = *Time::HiRes::stat;

sub store_ref {
    return savedatastore( $_[0], { 'data' => $_[1], ( ref $_[2] ? %{ $_[2] } : () ) } );
}

#
# *** Do not use fetch_ref in new code.
# It will silently discard data that is not
# in the format requested and return an empty
# reference.
#
# In order to be compatible with v64 behavior
# this function also returns a top level clone
# of the data.
#
# Its better to call
# Cpanel::CachedDataStore::loaddatastore and then call
# ->save on the object it returns (when loading locked)
#
sub fetch_ref {
    my ( $file, $is_array ) = @_;

    my $fetch_ref = loaddatastore($file);

    my $data_type = ref $fetch_ref->{'data'};
    #
    # As of v66:
    # Cpanel::API::DomainInfo
    # and other (there may be more) rely on fetch_ref
    # doing a top level clone.
    #
    my $data = $data_type ? top_level_clone( $fetch_ref->{'data'} ) : undef;
    $data_type ||= 'UNDEF';

    if ( $is_array && $data_type ne 'ARRAY' ) {
        return [];
    }
    elsif ( !$is_array && $data_type ne 'HASH' ) {
        return {};
    }

    return $data;
}

sub load_ref {
    my ( $file, $into_ref, $opts_ref ) = @_;
    my $fetch_ref = loaddatastore( $file, 0, $into_ref, $opts_ref );
    return $fetch_ref->{'data'};
}

sub savedatastore {
    my ( $file, $opts ) = @_;

    require Cpanel::SafeFile;
    my $use_cache_file = !defined $opts->{'cache_file'} || $opts->{'cache_file'};

    if ( !exists $opts->{'data'} || !defined $opts->{'data'} ) {
        Cpanel::Debug::log_warn("Expected data to be saved. \$opts->{'data'} was empty. $file has been left untouched.");
        if ( $opts->{'fh'} && $opts->{'safefile_lock'} ) {
            Cpanel::SafeFile::safeclose( $opts->{'fh'}, $opts->{'safefile_lock'} );
        }
        elsif ( $opts->{'fh'} ) {
            close( $opts->{'fh'} );
        }
        return;
    }

    my $use_memory_cache = !defined $opts->{'enable_memory_cache'} || $opts->{'enable_memory_cache'};

    my $original_file = $file;

    substr( $file, -5, 5, '' ) if rindex( $file, '.yaml' ) == length($file) - 5;

    require Cpanel::YAML;
    my $output = Cpanel::YAML::Dump( $opts->{'data'} );

    my $perms = exists $opts->{'mode'} ? $opts->{'mode'} & 00777 : undef;

    if ( !defined($perms) ) {
        if ( $opts->{'fh'} ) {
            die "Filehandle already closed!" if !defined fileno $opts->{'fh'};
            $perms = ( stat $opts->{'fh'} )[2] & 0777;
        }
        elsif ( -e $original_file ) {
            $perms = ( stat _ )[2] & 0777;
        }
        else {
            $perms = 0644;
        }
    }

    require Cpanel::FileUtils::Write;
    my $fh = Cpanel::FileUtils::Write::overwrite( $original_file, $output, $perms );
    @{$opts}{ 'inode', 'size', 'mtime' } = ( _stat($fh) )[ 1, 7, 9 ];
    close $fh;

    if ($use_cache_file) {

        _write_cache_file( "$file.cache", $opts->{'data'}, $perms );

        # We must set the mtime since we can cross the second
        # barrier during the serialize and write to disk which
        # would unexpectedly invalidate the cache because
        # it would be out of sync with the mtime of the
        # file it is a cache for.
        #
        # This is safe to adjust since we have not released the lock
        # or we are creating the datastore for the first time
        _utime( $opts->{'mtime'}, $opts->{'mtime'}, "$file.cache" );

    }

    # Update internal cache ONLY after we have written the file
    if ($use_memory_cache) {

        # We now restat the correct file so its ok to update the mtime and size in the memory
        # cache
        if ( $opts->{'size'} < $MAX_CACHE_OBJECT_SIZE ) {
            _cleanup_cache() if ++$_iterations_since_last_cache_cleanup > $MAX_CACHE_ELEMENTS && scalar keys %DATASTORE_CACHE >= $MAX_CACHE_ELEMENTS;
            @{ $DATASTORE_CACHE{$original_file} }{ 'cache', 'inode', 'mtime', 'size' } = @{$opts}{ 'data', 'inode', 'mtime', 'size' };
        }
        else {
            delete $DATASTORE_CACHE{$original_file};
        }
    }

    my $ok;
    if ( $opts->{'fh'} ) {
        if ( $opts->{'safefile_lock'} ) {
            $ok = Cpanel::SafeFile::safeclose( $opts->{'fh'}, $opts->{'safefile_lock'} );
        }
        else {
            $ok = close( $opts->{'fh'} );
        }
    }
    else {
        $ok = 1;
    }

    return $ok;
}

# This method will CREATE the $datastore_file if it does not exist.
#
# If $lock_required, then the lock and filehandle are in the return hash.
# If the YAML parse fails, "data" is undef.
#
# $copy_data_ref (optional) is a reference into which loaddatastore() will copy
# the data that it returns as "data" in the return hashref.
#
# TODO: Report YAML parsing failures somehow since callers need to know
# if the datastore is corrupt.
#
#opts:
#   enable_memory_cache - defaults to on
#   donotlock - defaults to inverse of $lock_required
#   mode - used when creating the $datastore_file, defaults to 0644
#return: A single hashref:
#   {
#       data: <ref>,
#       safefile_lock (when locking): return of Cpanel::SafeFile::safeopen(),
#       fh (when locking): The r/w filehandle,
#   }
sub loaddatastore {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my ( $datastore_file, $lock_required, $copy_data_ref, $opts ) = @_;

    my ( $loaded_data, $filesys_inode, $filesys_perms, $filesys_mtime, $filesys_size, $filesys_cache_mtime, $cache, $datastore_cache_file );

    if ( !$datastore_file ) {
        Cpanel::Debug::log_warn('No datastore file specified');
        return;
    }

    my $use_memory_cache = !defined $opts->{'enable_memory_cache'} || $opts->{'enable_memory_cache'};

    my $custom_perms = exists $opts->{'mode'} ? $opts->{'mode'} & 00777 : undef;

    my $lock_datastore = 0;    # default is to not lock
    if ( defined $lock_required ) {
        $lock_datastore = $lock_required ? 1 : 0;
    }
    elsif ( $opts->{'donotlock'} ) {
        $lock_datastore = 0;
    }

    # 1) Attempt to give the intended data from memory cache.
    if ( !$lock_datastore ) {
        ( $filesys_inode, $filesys_perms, $filesys_size, $filesys_mtime ) = ( _stat($datastore_file) )[ 1, 2, 7, 9 ];
        if ( !$filesys_mtime ) {

            # This fails silently
            return;
        }

        if (
            $use_memory_cache
            && exists $DATASTORE_CACHE{$datastore_file}    # no-auto vivify
            && $DATASTORE_CACHE{$datastore_file}->{'mtime'}
            && $DATASTORE_CACHE{$datastore_file}->{'size'}
            && $filesys_mtime == $DATASTORE_CACHE{$datastore_file}->{'mtime'}
            && $filesys_size == $DATASTORE_CACHE{$datastore_file}->{'size'}
            && $filesys_inode == $DATASTORE_CACHE{$datastore_file}->{'inode'}
        ) {
            if ($copy_data_ref) {
                _copy_ref_data( $DATASTORE_CACHE{$datastore_file}->{'cache'}, $copy_data_ref, $datastore_file );
            }

            #If we gave custom perms, then we need to ensure that the
            #filesystem mode matches the given perms.
            if ( defined $custom_perms ) {
                if ( ( $filesys_perms & 0777 ) != $custom_perms ) {
                    chmod $custom_perms, $datastore_file or do {
                        warn sprintf( "chmod(0%03o, $datastore_file): $!", $custom_perms );
                    };
                }
            }

            return bless {
                'size'  => $DATASTORE_CACHE{$datastore_file}->{'size'},
                'inode' => $DATASTORE_CACHE{$datastore_file}->{'inode'},
                'mtime' => $DATASTORE_CACHE{$datastore_file}->{'mtime'},
                'data'  => $DATASTORE_CACHE{$datastore_file}->{'cache'},
                'file'  => $datastore_file,
              },
              __PACKAGE__;
        }
    }

    $datastore_cache_file = $datastore_file;

    #If the path ends in “.yaml”, then swap that extension for “.cache”;
    #otherwise, just append “.cache”.

    if ( rindex( $datastore_cache_file, '.yaml' ) == length($datastore_cache_file) - 5 ) {
        substr( $datastore_cache_file, -5, 5, '.cache' );
    }
    else {
        $datastore_cache_file .= '.cache';
    }

    # 2) Attempt to give the intended data from on-disk cache.
    if ( !$lock_datastore ) {
        ( $filesys_cache_mtime, $cache ) = _load_datastore_cache_from_disk( $datastore_cache_file, $filesys_mtime, $datastore_file, $filesys_size, $filesys_inode );
        if ( $filesys_cache_mtime && $filesys_cache_mtime >= $filesys_mtime && ref $cache ) {
            $loaded_data = $cache;
        }

        if ( $copy_data_ref && $loaded_data ) {
            _copy_ref_data( $loaded_data, $copy_data_ref, $datastore_file );
        }

        if ($loaded_data) {
            if ( defined $custom_perms && ( $filesys_perms & 00777 ) != $custom_perms ) {
                chmod( $custom_perms, $datastore_file ) or do {
                    warn( sprintf "chmod(0%o, %s) failed: %s", $custom_perms, $datastore_file, $! );
                };
            }

            if ($use_memory_cache) {
                if ( $filesys_size < $MAX_CACHE_OBJECT_SIZE ) {
                    _cleanup_cache() if ++$_iterations_since_last_cache_cleanup > $MAX_CACHE_ELEMENTS && scalar keys %DATASTORE_CACHE >= $MAX_CACHE_ELEMENTS;
                    @{ $DATASTORE_CACHE{$datastore_file} }{ 'inode', 'size', 'mtime', 'cache' } = ( $filesys_inode, $filesys_size, $filesys_mtime, $loaded_data );
                }
                else {
                    delete $DATASTORE_CACHE{$datastore_file};
                }
            }

            return bless {
                'inode' => $filesys_inode,
                'size'  => $filesys_size,
                'mtime' => $filesys_mtime,
                'data'  => $loaded_data,
                'file'  => $datastore_file,
              },
              __PACKAGE__;

        }
    }

    #----------------------------------------------------------------------
    # Neither memory nor disk caches worked, so we have to load the
    # authoritative datastore.
    #----------------------------------------------------------------------

    my $datastore_not_writable;
    my $data_fh;
    my $perms = defined $custom_perms ? $custom_perms : 0644;    #0644 is the default
    my $orig_umask;
    if ( defined $perms ) {
        $orig_umask = umask( $perms ^ 07777 );
    }

    my $created_datastore_file = 0;

    # stat() is a bit faster than open(), and most of the time
    # this file should exist.
    if ( !-e $datastore_file ) {
        if ( sysopen my $f, $datastore_file, WRONLY_CREAT_EXCL, $perms ) {
            $created_datastore_file = 1;

            # TODO: At this point we know there’s no data to read.
            # Even if something comes along and writes $datastore_file
            # immediately after we just created it, that won’t update
            # our $created_datastore_file flag.
            #
            # If the caller wanted a lock, then it’s sensible to continue,
            # but if not, we should just return.
        }
        elsif ( $! != _EEXIST() ) {
            warn "Failed to create “$datastore_file” (EUID=$>): $!";

            # TODO: At this point we know there’s no file to read.
            # We should just return.
        }

        # TODO: We should only get here if sysopen failed with EEXIST
        # or if the caller wants a lock.
    }

    my $rlock;
    my $lock_failed;
    if ( !$lock_datastore ) {

        # file is already locked
        open( $data_fh, '<', $datastore_file ) or do {
            Cpanel::Debug::log_warn("Unable open $datastore_file for reading: $!");

            # TODO: At this point there’s nothing that we can read,
            # so we should just return.

            undef $data_fh;
        };
        $datastore_not_writable = 1;
    }
    else {
        my $open_mode = -w $datastore_file ? '+<' : '<';
        require Cpanel::SafeFile;
        $rlock = Cpanel::SafeFile::safeopen( $data_fh, $open_mode, $datastore_file );
        my $last_error = $@ || $!;
        $lock_failed = !$rlock || 1 == $rlock;

        if ($lock_failed) {
            Cpanel::Debug::log_warn("Unable get a lock on datastore $datastore_file: $last_error");

            # TODO: At this point there is no file handle,
            # so we should just return.

            undef $data_fh;
            $datastore_not_writable = 1;
        }
    }
    umask($orig_umask) if defined $orig_umask;

    if ( !$created_datastore_file ) {
        my $data_fh_perms = ( _stat( $data_fh // $datastore_file ) )[2] || 0600;

        # In case the original file had permissions other than what we want.  Don't
        # accidentally loosen the permissions on the file by using 644 if the
        # original file had more limited permissions.
        if ( defined $custom_perms && ( $data_fh_perms & 00777 ) != $custom_perms ) {
            chmod( $custom_perms, $data_fh ? $data_fh : $datastore_file );
            $data_fh_perms = ( _stat( $data_fh // $datastore_file ) )[2] || 0600;
        }

        if ( $data_fh && fileno $data_fh ) {
            if ($lock_datastore) {
                ( $filesys_inode, $filesys_perms, $filesys_size, $filesys_mtime ) = ( _stat($data_fh) )[ 1, 2, 7, 9 ];
                ( $filesys_cache_mtime, $cache ) = _load_datastore_cache_from_disk( $datastore_cache_file, $filesys_mtime, $datastore_file, $filesys_size, $filesys_inode );
            }
            if ( $filesys_cache_mtime && ref $cache ) {
                $loaded_data = $cache;
            }
            else {
                $loaded_data = _load_inner_data( $datastore_file, $data_fh );
                seek( $data_fh, 0, 0 );
            }
            if ( $copy_data_ref && $loaded_data ) {
                _copy_ref_data( $loaded_data, $copy_data_ref, $datastore_file );
            }
        }

        if ( !$lock_datastore || $datastore_not_writable ) {
            my @data_dir = split( /\/+/, $datastore_cache_file );
            pop @data_dir;
            my $datastore_cache_file_dir = join( '/', @data_dir );
            if ( $loaded_data && $filesys_mtime && ( !-e $datastore_cache_file || -w _ ) && ( _stat($datastore_cache_file_dir) )[4] == $> ) {
                _write_cache_file( $datastore_cache_file, $loaded_data, $data_fh_perms ) if !$filesys_cache_mtime;
                if ($use_memory_cache) {
                    if ( $filesys_size < $MAX_CACHE_OBJECT_SIZE ) {
                        _cleanup_cache() if ++$_iterations_since_last_cache_cleanup > $MAX_CACHE_ELEMENTS && scalar keys %DATASTORE_CACHE >= $MAX_CACHE_ELEMENTS;
                        @{ $DATASTORE_CACHE{$datastore_file} }{ 'cache', 'inode', 'mtime', 'size' } = ( $loaded_data, $filesys_inode, $filesys_mtime, $filesys_size );
                    }
                    else {
                        delete $DATASTORE_CACHE{$datastore_file};
                    }
                }
            }

        }
    }

    if ( !$lock_datastore || $datastore_not_writable ) {
        if ( !$lock_datastore ) {
            close($data_fh);
        }
        else {
            require Cpanel::SafeFile;
            Cpanel::SafeFile::safeclose( $data_fh, $rlock ) unless $lock_failed;
        }
        $data_fh                = undef;    # data_fh is closed at this point
        $datastore_not_writable = 1;        # if the datastore is closed, it isn't writable.
    }

    my %self = (
        'inode' => $filesys_inode,
        'size'  => $filesys_size,
        'mtime' => $filesys_mtime,
        'data'  => $loaded_data,
        'file'  => $datastore_file,
    );

    if ( !$datastore_not_writable ) {
        @self{ 'safefile_lock', 'fh' } = ( $rlock, $data_fh );
    }

    return bless \%self, __PACKAGE__;
}

sub _load_datastore_cache_from_disk {
    my ( $datastore_cache_file, $filesys_mtime, $datastore_file, $filesys_size, $filesys_inode ) = @_;
    my $loaded_data;
    if ( open( my $datastore_cache_fh, '<:stdio', $datastore_cache_file ) ) {
        my $filesys_cache_mtime = ( _stat($datastore_cache_fh) )[9];    # stat the file handle to prevent a race condition
        if ( $filesys_size && $filesys_mtime && $filesys_cache_mtime >= $filesys_mtime && $filesys_cache_mtime <= _time() ) {
            eval {
                local $SIG{'__DIE__'};     # Suppress spewage as we may be reading an invalid cache
                local $SIG{'__WARN__'};    # and since failure is ok to throw it away
                $loaded_data = Cpanel::AdminBin::Serializer::LoadFile($datastore_cache_fh);
            };
            my ( $filesys_inode_after_read, $filesys_size_after_read, $filesys_mtime_after_read ) = ( _stat($datastore_file) )[ 1, 7, 9 ];

            # If it changed after we read the cache then we cannot use it
            if (   $filesys_mtime_after_read == $filesys_mtime
                && $filesys_size_after_read == $filesys_size
                && $filesys_inode_after_read == $filesys_inode ) {
                return ( $filesys_cache_mtime, $loaded_data ) if ref $loaded_data;
            }
        }

    }
    elsif ( $! != _ENOENT() ) {    #ok if the file does not exist
        warn "Failed to open “$datastore_cache_file” for reading: $!";
    }

    return 0;
}

sub _write_cache_file {
    my ( $path, $data, $perms ) = @_;

    # SSLStorage checks $LAST_WRITE_CACHE_FAILED
    # to see if it needs to validate the data is
    # JSON safe
    $LAST_WRITE_CACHE_SERIALIZATION_ERROR = undef;

    try {
        my $serialized;

        try {
            $serialized = Cpanel::AdminBin::Serializer::Dump($data);
        }
        catch {
            $LAST_WRITE_CACHE_SERIALIZATION_ERROR = Cpanel::Exception::get_string($_);
        };

        if ($serialized) {
            require Cpanel::FileUtils::Write;
            Cpanel::FileUtils::Write::overwrite(
                $path,
                $serialized,
                $perms,
            );
        }
    }
    catch {
        my $str = Cpanel::Exception::get_string($_);
        Cpanel::Debug::log_warn("Failed to write the cache file “$path” ($str); this file will not be saved.");
    };

    return;
}

sub file {
    return $_[0]->{'file'};
}

sub fh {
    return $_[0]->{'fh'};
}

sub mtime {
    return $_[0]->{'mtime'};
}

sub size {
    return $_[0]->{'size'};
}

sub clear_data {
    $_[0]->{'data'} = undef;
    return;
}

sub data {
    if ( defined $_[1] ) {
        $_[0]->{'data'} = $_[1];
        return 1;
    }
    return $_[0]->{'data'};
}

sub save {
    return savedatastore( $_[0]->{'file'}, $_[0] );
}

sub abort {
    return unlockdatastore( $_[0] );
}

sub unlockdatastore {
    my ($datastore) = @_;

    return 0 if !$datastore->{'fh'} || !$datastore->{'safefile_lock'};

    require Cpanel::SafeFile;
    return Cpanel::SafeFile::safeclose( $datastore->{'fh'}, $datastore->{'safefile_lock'} );
}

sub _copy_ref_data {
    my ( $src_ref, $dest_ref, $file ) = @_;

    if ( ref $src_ref eq 'HASH' ) {
        local $@;
        eval { %{$dest_ref} = %{$src_ref}; };

        # Cpanel::Debug::log_warn("Failed to copy into HASH reference: $@") if $@;

    }
    elsif ( ref $src_ref eq 'ARRAY' ) {
        local $@;
        eval { @{$dest_ref} = @{$src_ref}; };

        # Cpanel::Debug::log_warn("Failed to copy into ARRAY reference: $@") if $@;
    }
    else {
        if ($file) {
            Cpanel::Debug::log_warn("YAML in '$file' is not a hash or array reference");
        }
        else {
            Cpanel::Debug::log_warn('Asked to duplicate a reference that is not a hash or array');
        }
        $dest_ref = $src_ref;
    }
    return;
}

#Not for production use; only for testing.
sub get_cache {
    return \%DATASTORE_CACHE;
}

sub clear_cache {
    %DATASTORE_CACHE = ();
    return;
}

sub clear_one_cache {
    my ($file) = @_;

    delete $DATASTORE_CACHE{$file};
    return;
}

sub verify {
    my ($file) = @_;

    my $fh;
    open( $fh, '<', $file ) or die "Failed to open $file: $!";

    my $data = _load_inner_data( $file, $fh );

    return ref $data ? 1 : 0;
}

sub _load_inner_data {
    my ( $name, $fh ) = @_;
    my $data = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $fh, $data );
    my $loaded_data;

    if ( length $data ) {
        local $@;
        eval {
            local $SIG{'__WARN__'};
            local $SIG{'__DIE__'};
            require Cpanel::YAML;
            $loaded_data = ( Cpanel::YAML::Load($data) )[0];
        };
    }

    $loaded_data = undef unless ref $loaded_data;
    return $loaded_data;
}

# A lighter clone that only
# makes a copy at the top level
sub top_level_clone {
    my ($data) = @_;

    if ( ref $data eq 'HASH' ) {
        return { %{ $_[0] } };
    }
    elsif ( ref $data eq 'ARRAY' ) {
        return [ @{ $_[0] } ];
    }

    return $data;
}

sub _cleanup_cache {
    my @oldest_keys = sort { $DATASTORE_CACHE{$b}{'mtime'} <=> $DATASTORE_CACHE{$a}{'mtime'} } keys %DATASTORE_CACHE;
    splice( @oldest_keys, -1 * int( $MAX_CACHE_ELEMENTS / 2 ) );
    delete @DATASTORE_CACHE{@oldest_keys};
    $_iterations_since_last_cache_cleanup = 0;
    return 1;
}

sub _ENOENT { return 2; }
1;
