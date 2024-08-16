package Cpanel::Sync::v2;

# cpanel - Cpanel/Sync/v2.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Carp                        ();
use Cpanel::Config::CpConfGuard ();
use Cpanel::LoadFile            ();
use Cpanel::Exception           ();
use Cpanel::FileUtils::Write    ();
use Cpanel::HttpRequest         ();
use Cpanel::LoadModule          ();
use Cpanel::SafeDir::MK         ();
use Cpanel::SafeDir::RM         ();
use Cpanel::Sys::Chattr         ();
use Cpanel::TempFile            ();
use Cpanel::JSON                ();
use Cpanel::Fcntl::Types        ();
use Cpanel::Fcntl::Constants    ();
use File::Basename              ();
use File::Copy                  ();
use File::Spec                  ();
use IO::Handle                  ();
eval {
    local $SIG{'__DIE__'};
    local $SIG{'__WARN__'};
    require Cpanel::YAML;          # PPI NO PARSE - We need updatenow.static to build this in
    require Cpanel::YAML::Syck;    # PPI NO PARSE - We need updatenow.static to build this in
};

use Try::Tiny;
use parent 'Cpanel::Update::Base';

use constant S_IFMT => $Cpanel::Fcntl::Constants::S_IFMT;

=head1 NAME

Cpanel::Sync::v2 - sync from multiple sources to the same dest dir at once.

=head1 NOTE

NOTE: cPanel Sync v2 is subject to change or removal at any time without notice so proceed with caution!

=head1 SYNOPSIS

    $0 cpsync2
       url http://httpupdate.cpanel.net/cpanelsync/NN.NN.NN
       source cpanel
       source binaries/linux-i386
       syncto /usr/local/cpanel

    Optional:
       verbose => 2
           By default only errors are output. Specify once to get verbose information, specify twice to add addition debug type output (prefaced with "DEBUG")

=cut

our $VERSION = '4.03';

my $STATE_FAILED = 0;
my $STATE_OK     = 1;

our $STATE_KEY_POSITION      = 0;
our $STAGED_DIR_KEY_POSITION = 1;

our $USE_HASH_CACHE    = 0;
our $IGNORE_HASH_CACHE = 1;

my $STREAM_MEMORY_LIMIT = 1024**2 * 4;    # 4MiB

## Package global; redefined in unit tests
sub cpanelsync_excludes_file      { return '/etc/cpanelsync.exclude' }
sub cpanelsync_chmod_exclude_file { return '/etc/cpanelsync.no_chmod' }

=head1 METHODS

=over 4

=item B<new>

Called from updatenow mostly, with $options from returned from parse_argv

=cut

sub new ( $class, $args ) {

    ref($args) eq 'HASH' or die("Hash ref not passed into Cpanel::Sync::v2->new");

    # Validate required parameters are passed
    foreach my $param (qw( syncto url source logger)) {
        $args->{$param} or die( "Cannot create " . __PACKAGE__ . " without $param parameter" );
    }
    ref( $args->{'source'} ) eq 'ARRAY' or die("Required array ref not passed to new as 'source'");
    @{ $args->{'source'} }              or die("Required array ref passed to new as 'source' is empty");

    $args->{'stage_suffix'} ||= '-cpanelsync';

    $args->{'url'} =~ m{https?://([^/]+)(.*)} or die("Cannot parse url: $args->{'url'}");
    $args->{'host'} = $1;
    $args->{'url'}  = $2;
    $args->{'options'} ||= {};

    # Detect if optional modules are present - Digest::MD5, Digest::SHA, Cpanel::IO::Mmap::Read
    #
    eval { require Digest::SHA;            $args->{'hassha'}  = 1 };
    eval { require Cpanel::IO::Mmap::Read; $args->{'hasmmap'} = 1; };

    if ( $args->{'http_client'} ) {
        $args->{'http_client'}->isa('Cpanel::HttpRequest') or die "http_client must be a Cpanel::HttpRequest";
    }

    # Assure 4 needed binaries are present - bzip2, xz, gzip, sha512sum
    my @required_binaries = qw/bzip2 sha512sum gzip/;
    push @required_binaries, 'xz' unless $args->{'options'}{'ignore_xz'};
    foreach (@required_binaries) {
        -x "/usr/bin/$_" or die("This program cannot function without an executable /usr/bin/$_");
    }

    my $conf = Cpanel::Config::CpConfGuard->new( 'loadcpconf' => 1 )->config_copy;

    # Setup the default sync_basename and prepend anything passed in with .cpanelsync
    $args->{'sync_basename'} = '.cpanelsync';

    unlink "$args->{'syncto'}/$args->{'sync_basename'}.new";
    if ( -e "$args->{'syncto'}/.cpanelsync.new" ) {
        $args->{'logger'}->warning("Could not remove previous temp cpanelsync file '$args->{'syncto'}/$args->{'sync_basename'}.new': $!");
        $args->{'logger'}->set_need_notify();
    }

    my $self = bless $args, $class;

    chop $self->{'staging_dir'} while substr( $self->{'staging_dir'}, -1 ) eq '/';
    $self->{'staging_dir_length'}  = length $self->{'staging_dir'};
    $self->{'stage_suffix_length'} = length $self->{'stage_suffix'};
    $self->{'staging_dir_is_ulc'}  = $self->{'staging_dir'} eq $self->{'ulc'} ? 1 : 0;

    # Normalize the paths in the file.
    $self->{'source_data'}->{'excludes'}       = $self->_get_excludes( cpanelsync_excludes_file() );
    $self->{'source_data'}->{'chmod_excludes'} = $self->_get_excludes( cpanelsync_chmod_exclude_file() );

    $self->{'master_pid'} = $$;

    # Format of 'staged_directories'
    #   Staged Dir => Target Dir
    $self->{'staged_directories'} = {};

    # Format of 'staged_files'
    #   Staged File => [ OK OR FAILED, Staged Dir ]
    $self->{'staged_files'} = {};

    return $self;
}

sub _create_http_client ($self) {
    return $self->{'http_client'} ||= Cpanel::HttpRequest->new(
        'die_on_404'      => 1,
        'retry_dns'       => 0,
        'hideOutput'      => $self->{'http_verbose'} ? 0 : 1,
        'logger'          => $self->{'logger'},
        'announce_mirror' => 1,
    );
}

=item B<_get_excludes>

Loads an exclude file and returns a key populated hash with full paths to the excluded files

=cut

sub _get_excludes ( $self, $file ) {
    $file or die;

    return undef if ( !-e $file || -z _ || -d _ );
    my %excludes;

    open( my $fh, '<', $file ) or return {};
    while ( my $line = <$fh> ) {
        next if $line =~ m/^\s*$/;
        chomp $line;
        $line =~ s/\s+$//;    #remove whitespace
        $line =~ s/^\s+//;
        $excludes{ $self->_normalize_syncfile_path($line) } = 1;
    }
    close($fh);

    return undef if !( scalar keys %excludes );

    return \%excludes;
}

sub get_source_list ($self) { return $self->{'source'}->@* }

sub get_hash ( $self, $file, $relative_path, $use_cache = $USE_HASH_CACHE, $file_info = undef ) {    ## no critic qw(Subroutines::ProhibitManyArgs)
    $file_info //= $self->get_target_info($file);

    # Only normal files have a digest
    return '' if !$file_info->{'exists'} || !$file_info->{'isnormfile'};

    substr( $relative_path, -24, 24, '' ) if substr( $relative_path, -24 ) eq '.cpanelsync.nodecompress';
    $self->{'digest_lookup'}->{$relative_path} ||= {};
    my $digest_cache = $self->{'digest_lookup'}->{$relative_path};

    if (
           $use_cache == $USE_HASH_CACHE
        && $digest_cache->{'sha'}                               # Skip cache if no hash value in cache
        && defined $digest_cache->{'mtime'}
        && $file_info->{'mtime'} == $digest_cache->{'mtime'}    # Skip cache if mtime of file is not the same as what cache has.
        && defined $digest_cache->{'size'}
        && $file_info->{'size'} == $digest_cache->{'size'}
      ) {                                                       # Skip cache if size in cache is not the same as the current file size
        $digest_cache->{'used'} = 1;
        return $digest_cache->{'sha'};
    }

    my $hash = $self->{'hassha'} ? $self->_get_checksum_lib( $file, $file_info->{'size'} ) : $self->_get_checksum_binary($file);
    @{$digest_cache}{ 'size', 'mtime', 'sha', 'used' } = ( $file_info->{'size'}, $file_info->{'mtime'}, $hash, 1 );

    return $hash;
}

sub _get_checksum_binary ( $self, $file ) {

    my $bin = '/usr/bin/sha512sum';
    open( my $bin_fh, '-|' ) || exec $bin, $file;

    my $line = <$bin_fh>;
    my ($hash) = split( /\s+/, $line );

    close($bin_fh);
    return $hash;

}

sub _get_checksum_lib ( $self, $file, $size ) {

    my $ctx = Digest::SHA->new(512);
    my ( $hash, $has_bytes_read );

    if ( open( my $fh, '<', $file ) ) {
        if ( $self->{'hasmmap'} && $size > 16384 ) {
            my ( $bytes_read, $buffer );
            my $obj = Cpanel::IO::Mmap::Read->new($fh);
            while ( $bytes_read = $obj->read( $buffer, $STREAM_MEMORY_LIMIT ) ) {
                $has_bytes_read = $bytes_read;
                $ctx->add($buffer);
            }
        }
        elsif ( $ctx->addfile($fh) ) {
            $has_bytes_read = 1;
        }

        # Only get a digest if you read the entire file.
        if ($has_bytes_read) {
            $hash = $ctx->hexdigest();
        }
        else {
            $hash = '';
            $self->{'logger'}->error("Unable to read file ($file) to validate it's signature!");
            $self->{'logger'}->set_need_notify();
        }
    }
    else {
        $hash = '';
        $self->{'logger'}->error("Unable to open $file to get it's checksum: $!");
        $self->{'logger'}->error( "Stat: " . `stat '$file'` );    ## no critic qw(ProhibitQxAndBackticks) give more debug info

        $self->{'logger'}->set_need_notify();
        return '';
    }

    return $hash;
}

sub parse_new_cpanelsync_files ($self) {

    return $self if $self->{'already_ran_parse_new_cpanelsync_files'};

    # cpanel, x3, etc.
    for my $source ( $self->get_source_list() ) {
        my $sync_file      = $self->get_local_cpanelsync_file_name($source);
        my $temp_sync_file = $sync_file . $self->{'stage_suffix'};

        my %sync;
        foreach my $line ( split( m{\n}, Cpanel::LoadFile::load($temp_sync_file) ) ) {
            my ( $rtype, $rfile, $rperm, $rextra, $sha ) = split( /===/, $line, 5 );
            next if !$rtype || ( index( $rtype, '.' ) > -1 && $rtype =~ m/^\s*\.\s*$/ );

            # s{./foo}{/usr/local/cpanel/foo};
            $sync{ $self->_normalize_syncfile_path($rfile) } = {
                'file' => $rfile,
                'type' => $rtype,
                ## using %04d as $rperm is a string (comes from the .cpanelsync file)
                'perm'  => sprintf( '%04d', $rperm ),
                'extra' => $rextra,
                'sha'   => $sha,
            };
        }

        #  to prevent mass deletion on an inadvertantly empty or corrupt .cpanelsync
        if ( !%sync ) {
            $self->{'logger'}->fatal("$sync_file unexpectedly had no data.");
            die("Cannot continue without valid data from $sync_file");
        }
        $self->{'source_data'}->{'sync_file_data'}->{$source} = \%sync;
    }

    $self->{'already_ran_parse_new_cpanelsync_files'} = 1;

    return $self;
}

sub already_done ($self) {

    # if the syncto directory doesn't exist, then this is definitely not done #
    return 0 if !-d $self->{'syncto'};

    # we need the manifest and to parse it for this to work #
    $self->stage_cpanelsync_files();
    $self->parse_new_cpanelsync_files();

    foreach my $source ( keys %{ $self->{'source_data'}->{'sync_file_data'} } ) {
        foreach my $file ( keys %{ $self->{'source_data'}->{'sync_file_data'}->{$source} } ) {

            # skip symlinks, they may point to files outside this source tree #
            next if -l $file;

            # otherwise the file/dir should exist #
            return 0 if !-e $file;
        }
    }

    return 1;
}

sub is_excluded ( $self, $path ) {
    $path or die;
    return if !$self->{'source_data'}->{'excludes'};
    return $self->syncfile_path_is_excluded( $path, $self->{'source_data'}->{'excludes'} );
}

sub is_excluded_chmod ( $self, $path ) {
    $path or die;

    return if !$self->{'source_data'}->{'chmod_excludes'};
    return $self->syncfile_path_is_excluded( $path, $self->{'source_data'}->{'chmod_excludes'} );
}

sub commit_directories ($self) {

    my $logger = $self->{'logger'};

    # Put staged directories in place.
    foreach my $staged_dir ( keys %{ $self->{'staged_directories'} } ) {
        my $commit_to   = $self->{'staged_directories'}->{$staged_dir};
        my $target_info = $self->get_target_info($commit_to);
        if ( $target_info->{'islnk'} || $target_info->{'isnormfile'} ) {
            unlink $target_info->{'path'};
            $target_info->{'exists'} = 0;
        }

        if ( -d $commit_to ) {
            $logger->error("$commit_to was unexpectedly put in place while staging files for update");
            $logger->set_need_notify();
        }

        if ( File::Copy::move( $staged_dir, $commit_to ) ) {
            delete $self->{'staged_directories'}{$staged_dir};    # remove it once it has been commited
        }
        else {
            $logger->error("Could not rename $staged_dir -> $commit_to: $!");
            $logger->set_need_notify();
        }
    }

    for my $source ( $self->get_source_list() ) {
        my $cpanelsync_data = $self->{'source_data'}->{'sync_file_data'}->{$source};
        foreach my $full_path ( keys %$cpanelsync_data ) {
            my $cpanelsync_file = $cpanelsync_data->{$full_path};
            next if ( !$cpanelsync_file->{'type'} || $cpanelsync_file->{'type'} ne 'd' );

            my $target_info = $self->get_target_info( $self->_convert_path_to_ulc($full_path) );

            # Remove file or dir if it's already there.
            unlink( $target_info->{'path'} ) if ( !$target_info->{'isdir'} && $target_info->{'exists'} );

            # mkdir
            if ( !$target_info->{'isdir'} ) {

                # Make the directory.
                Cpanel::SafeDir::MK::safemkdir( $target_info->{'path'}, $cpanelsync_file->{'perm'}, 2 );
                $self->{'logger'}->info("Created directory $target_info->{'path'} successfully");
            }    # TODO: This logic was REALLY backwards? Validate.
            else {
                $self->chmod( $cpanelsync_file->{'perm'}, $target_info );
            }
        }
    }

    $self->{'logger'}->info("All directories created and updated");
    return 1;
}

sub commit_files ($self) {

    my @files_to_commit = keys %{ $self->{'staged_files'} };

    $self->{'logger'}->info( "Commiting all downloaded files for " . join( ", ", $self->get_source_list() ) );

    # Put the version files in place last.
    @files_to_commit = sort { return 1 if ( $a =~ m{/version$} ); return -1 if ( $b =~ m{/version$} ); $a cmp $b } @files_to_commit;

    foreach my $commit_to (@files_to_commit) {
        my $cpanelsync_status = $self->{'staged_files'}->{$commit_to};
        my ( $stage_path, $temp_file ) = $self->_calculate_stage_path_and_temp_file_from_stage_file($commit_to);
        my $target_info = $self->get_target_info( $self->_convert_path_to_ulc($commit_to) );
        my $commit_path = $target_info->{'path'};

        # TODO: We hash the file during stage. Should we check it again here?
        # What if it's wrong? what do we do then?

        # Handle unexpected dir or link being where we need to move it.
        if ( $target_info->{'isdir'} ) {
            Cpanel::SafeDir::RM::safermdir($commit_path);    # TODO: error check
            $target_info = $self->get_target_info( $self->_convert_path_to_ulc($commit_path) );
        }

        # Remove the old file and move it out of the way if the doesn't work.
        if ( $target_info->{'exists'} ) {
            unlink $commit_path;
            $target_info = $self->get_target_info( $self->_convert_path_to_ulc($commit_path) );

            # Sometimes the file can be renamed when it can't be removed.
            if ( $target_info->{'exists'} ) {
                $self->{'logger'}->error("Failed to remove $commit_path to install the new version of this file. Trying to move it out of the way...");
                $self->{'logger'}->debug(`lsattr '$commit_path'`) if -x '/usr/bin/lsattr';    ## no critic qw(ProhibitQxAndBackticks) - just debug.
                $self->{'logger'}->debug(`ls -ld '$commit_path'`);                            ## no critic qw(ProhibitQxAndBackticks) - just debug.
                $self->{'logger'}->set_need_notify();

                if ( rename( $commit_path, $commit_path . '.unlink' ) ) {
                    $self->{'logger'}->error("$commit_path has been renamed to $commit_path.unlink. You should try to remove it.");
                    unlink $commit_path . '.unlink';
                }
                else {
                    $self->{'logger'}->error("Could not rename $commit_path out of the way. Please resolve and re-run /usr/local/cpanel/scripts/upcp --force.");
                    unlink $commit_path;
                }
            }
        }

        my $message = '';

        # File::Copy::move does a 'rename' first, and if it fails (when moving across devices, etc)
        # then it will automatically fallback to copy() and unlink().
        if ( !File::Copy::move( $temp_file, $commit_path ) ) {
            $message = $!;
            unlink $temp_file;

            if ( $self->is_file_immutable($commit_path) ) {
                $self->{'logger'}->error("$commit_path could not be overwritten by staged $temp_file");
                $self->{'logger'}->set_need_notify();
            }
            else {
                $self->{'logger'}->error("Could not put new '$commit_path' into place from $temp_file: $message");
                $self->{'logger'}->set_need_notify();
            }
        }
        else {

            # put new file into new files list
            push @{ $self->{'new_files'} }, $commit_path;
        }

        delete $self->{'staged_files'}{$commit_to};    # remove it once it has been commited
    }
    return;
}

sub handle_symlinks ($self) {

    for my $source ( $self->get_source_list() ) {
        my $cpanelsync_data = $self->{'source_data'}->{'sync_file_data'}->{$source};
        foreach my $path ( keys %$cpanelsync_data ) {
            my $cpanelsync_file = $cpanelsync_data->{$path};
            next if ( !$cpanelsync_file->{'type'} || $cpanelsync_file->{'type'} ne 'l' );

            my $link_to     = $cpanelsync_file->{'extra'};
            my $target_info = $self->get_target_info( $self->_convert_path_to_ulc($path) );

            # Remove file/dir/link if in the way.
            if ( $target_info->{'islnk'} ) {

                # The symlink is already there. No further action required.
                next if ( readlink $target_info->{'path'} eq $link_to );

                unlink $target_info->{'path'};
            }
            elsif ( $target_info->{'isnormfile'} ) {
                unlink $target_info->{'path'};
            }
            elsif ( $target_info->{'isdir'} ) {
                Cpanel::SafeDir::RM::safermdir( $target_info->{'path'} );
            }

            # Setup the symlink.
            if ( symlink( $cpanelsync_file->{'extra'}, $target_info->{'path'} ) ) {
                $self->{'logger'}->info("Created symlink $target_info->{'path'} -> $link_to successfully");
            }
            else {
                $self->{'logger'}->error("Failed to create symlink $target_info->{'path'} -> $link_to: $!");
                $self->{'logger'}->set_need_notify();
            }
        }
    }
    return;
}

sub validate_file_permissions ($self) {

    $self->{'logger'}->info("Checking permissions of all files we manage");
    for my $source ( $self->get_source_list() ) {
        my $cpanelsync_data = $self->{'source_data'}->{'sync_file_data'}->{$source};
        for my $full_path ( grep { $cpanelsync_data->{$_}{'type'} eq 'f' } keys %$cpanelsync_data ) {
            my $ulc_path    = $self->_convert_path_to_ulc($full_path);
            my $target_info = $self->{'get_target_info_cache_hash_checked'}{$ulc_path} || $self->get_target_info($ulc_path);
            next if !$target_info->{'exists'};
            $self->chmod( $cpanelsync_data->{$full_path}->{'perm'}, $target_info );
        }
    }

    delete $self->{'get_target_info_cache_hash_checked'};

    return;
}

sub is_file_immutable ( $self, $file ) {
    $file or die;

    open( my $fh, '<', $file ) or do {
        warn "open(< $file): $!" if !$!{'ENOENT'};
        return;
    };
    my $attr = grep { Cpanel::Sys::Chattr::get_attribute( $fh, $_ ) } qw( IMMUTABLE APPEND );
    close $fh;

    return 1 if $attr;
    return;
}

=item B<get_target_info>

Get permission, size and mtime on a file. Also set flag if file is a symlink or directory. Returns a hash reference.

=cut

my %_filetype_keymap = ( 'dir' => 'isdir', 'file' => 'isnormfile', 'link' => 'islnk' );

sub get_target_info ( $self, $normalized_path ) {
    $normalized_path or die;

    my %target = ( 'path' => $normalized_path, 'isdir' => 0, 'isnormfile' => 0, 'islnk' => 0, 'exists' => 0 );
    ## two slices to assign @_lstat indexes into %target
    @target{ 'perm', 'uid', 'gid', 'size', 'mtime' } = ( lstat( $target{'path'} ) )[ 2, 4, 5, 7, 9 ];

    # if it was a symlink lstat didn't fall back to stat and we got the info on the
    # symlink instead of the info we wanted.  We call lstat as we know it will give the
    # information for the file if its not a symlink and -l will still work.  This saves us
    # from having to stat the file twice if its not a symlink which will be most of the time.
    if ( $target{'perm'} ) {
        $target{'exists'} = 1;
        $target{ $_filetype_keymap{ $Cpanel::Fcntl::Types::FILE_TYPES{ S_IFMT & $target{'perm'} } } || 'isunknown' } = 1;
    }

    $target{uid} //= -1;
    $target{gid} //= -1;

    return \%target;

}

# Tested directly
sub _convert_path_to_ulc ( $self, $path ) {
    return undef if !defined $path;

    my $staging_dir_with_trailing_slash = $self->{'staging_dir'} . '/';

    if ( !$self->{'staging_dir_is_ulc'} && rindex( $path, $staging_dir_with_trailing_slash, 0 ) == 0 ) {
        substr( $path, 0, $self->{'staging_dir_length'}, $self->{'ulc'} );
    }
    return substr( $path, -$self->{'stage_suffix_length'} ) eq $self->{'stage_suffix'} ? substr( $path, 0, -$self->{'stage_suffix_length'} ) : $path;
}

sub _convert_path_to_staging ( $self, $path ) {
    $path =~ s/^$self->{'ulc'}/$self->{'staging_dir'}/;
    return $path;
}

sub create_dot_new_file ($self) {

    my $new_file = "$self->{'syncto'}/.cpanelsync.new";
    unless ( exists $self->{'new_files'} && ref( $self->{'new_files'} ) eq 'ARRAY' ) {
        $self->{'logger'}->debug("No new files to manifest");
        return 1;
    }

    my $new_fh;
    unless ( open( $new_fh, '>', $new_file ) ) {
        $self->{'logger'}->fatal("Could not open '$new_file' for writing: $!");
        die("Cannot continue without $new_file");
    }

    for ( sort @{ $self->{'new_files'} } ) {
        print {$new_fh} "$_\n";
    }
    return close($new_fh);
}

sub init_current_digest_cache ($self) {

    my $digest_lookup = $self->{'digest_lookup'} = {};

    # Don't use the digest cache if 'force' was passed in as true from updatenow.
    return if ( $self->{'force'} );

    my $digest_file = "$self->{'syncto'}/.cpanelsync.digest";

    return if ( !-e $digest_file );    # No MD5 is fine.

    $self->{'logger'}->info("Loading digest cache from $self->{'syncto'}/.cpanelsync.digest");
    foreach ( split( m{\n}, Cpanel::LoadFile::load($digest_file) ) ) {
        my ( $filename, $size, $mtime, undef, $sha ) = split( /:::/, $_, 5 );
        $digest_lookup->{$filename} = {
            'size'  => $size,
            'mtime' => $mtime,
            'sha'   => $sha,
        };
    }
    return;
}

sub save_updated_digest_data ($self) {

    my $digest_file   = "$self->{'syncto'}/.cpanelsync.digest";
    my $digest_lookup = $self->{'digest_lookup'};
    my $contents      = '';
    foreach my $relative_path ( sort keys %{$digest_lookup} ) {
        next
          if (
            !$digest_lookup->{$relative_path}{'used'}         ||    # Don't save the cache of a file we didn't use this time around
            !defined $digest_lookup->{$relative_path}{'size'} ||    # Don't save if size is undefined
            !$digest_lookup->{$relative_path}{'mtime'}        ||    # Don't save if mtime is false
            !$digest_lookup->{$relative_path}{'sha'}
          );                                                        # Don't' save if no hash
        my $cache_str = join(
            ':::',
            $relative_path,
            $digest_lookup->{$relative_path}{'size'},
            $digest_lookup->{$relative_path}{'mtime'}
        );

        $cache_str .= '::::::';

        if ( $digest_lookup->{$relative_path}{'sha'} ) {
            $cache_str .= $digest_lookup->{$relative_path}{'sha'};
        }

        $cache_str .= "\n";
        $contents  .= $cache_str;
    }

    try {
        Cpanel::FileUtils::Write::overwrite( $digest_file, $contents, 0644 );
    }
    catch {
        local $@ = $_;
        my $err = Cpanel::Exception::get_string($_);
        $self->{'logger'}->fatal("Could not open '$digest_file' for writing: $err.");
        die;
    };
    return;
}

sub _normalize_syncfile_path ( $self, $path_from_syncfile ) {
    length $path_from_syncfile or Carp::croak('[ARGUMENT] path_from_syncfile must be specified');

    chop $path_from_syncfile while substr( $path_from_syncfile, -1 ) eq '/';    # Strip off the trailing slash from the path_from_syncfile.
    substr( $path_from_syncfile, -24, 24, '' ) if substr( $path_from_syncfile, -24 ) eq '.cpanelsync.nodecompress';
    return rindex( $path_from_syncfile, '.', 0 ) == 0 ? $self->{'syncto'} . substr( $path_from_syncfile, 1 ) : $path_from_syncfile;
}

sub syncfile_path_is_excluded ( $self, $path, $normalized_exclude_lookup_hr ) {    ## no critic qw(Subroutines::ProhibitManyArgs)
    $path                         or die;
    $normalized_exclude_lookup_hr or die;

    my $full_path = $self->_normalize_syncfile_path($path);
    return 1 if $normalized_exclude_lookup_hr->{$full_path};

    while (1) {
        my $copy = $full_path;
        $full_path =~ s{/[^/]+$}{};
        last if !$full_path || $full_path eq '/' || $copy eq $full_path;

        return 1 if ( $normalized_exclude_lookup_hr->{$full_path} );
    }

    return;
}

sub chmod ( $self, $plaintext_octal_perms, $file_info, $check_exclusions = undef ) {    ## no critic qw(Subroutines::ProhibitManyArgs)
    $plaintext_octal_perms ||= 0;
    $file_info or die;
    $check_exclusions = !$check_exclusions;

    my $full_path = $file_info->{'path'};
    return 0 unless ( $file_info->{'exists'} );
    return 0 if ( $file_info->{'islnk'} );

    # Short early if the current file perms are already what they need to be.
    my $decimal_perms_needed = oct($plaintext_octal_perms);
    return 0 if ( $decimal_perms_needed == ( $file_info->{'perm'} & 07777 ) );

    # Is it excluded from chmod?
    if ( $check_exclusions && $self->{'source_data'}->{'chmod_excludes'} && $self->syncfile_path_is_excluded( $full_path, $self->{'source_data'}->{'chmod_excludes'} ) ) {
        $self->{'logger'}->warning("$full_path is prevented from chmod");
        return 0;
    }

    # chmod only
    unless ( CORE::chmod( $decimal_perms_needed, $full_path ) ) {
        $self->{'logger'}->error("Failed to update permissions for $full_path to $plaintext_octal_perms: $!");
        $self->{'logger'}->set_need_notify();
        return 0;
    }

    if ( $self->{'verbose'} && $self->{'verbose'} >= 2 ) {
        $self->{'logger'}->info("Set permissions on $full_path to $plaintext_octal_perms");
    }

    return 1;
}

sub chown ( $self, $uid, $gid, $full_path ) {

    # Nothing to do.
    return 1 if $uid == -1 && $gid == -1;

    unless ( CORE::chown( $uid, $gid, $full_path ) ) {
        $self->{'logger'}->error("Failed to update ownership for $full_path to $uid:$gid: $!");
        $self->{'logger'}->set_need_notify();
        return 0;
    }
    $self->{'logger'}->info("Set ownership on $full_path to $uid:$gid") if $uid || $gid;
    return 1;
}

# Detects if something along the line between syncto and our file is a symlink
# Warning: This function caches which files have changed since it was the slowest
# part of the sync process.  If its possible that something in the path may
# no longer be a symlink in the middle of a sync (this should never happen since
# we only call this from handle_removed_files) this function will return
# unexpected results.  As long as handle_removed_files is the only caller this should
# never be a problem
sub _symlink_in_path_during_handle_removed_files ( $self, $original_path ) {
    $original_path or die;

    my @parts = split( m{/+}, $original_path );
    my $path;
    my $ulc_path_syncto = $self->_convert_path_to_ulc( $self->{'syncto'} );
    while ( pop(@parts) ) {
        $path = join( '/', @parts );

        return if $path eq $ulc_path_syncto;

        # Something's really gone wrong if this happens but let's not encourage the calling sub to do anything if this happens.
        return 2 if length($path) < length($ulc_path_syncto);

        return 1 if ( $self->{'symlink_cache'}{$path} //= ( -l $path ? 1 : 0 ) );    # Something along the path to this file is a symlink.
    }

    # Unreachable
    return 2;
}

# Double-check the list of candidates for deletion against the complete set of sources,
# and delete those that are not found.
sub handle_removed_files ($self) {

    my @files_to_remove;
    my @directories_to_remove;
    my @source_list = $self->get_source_list();
    my $syncdata    = $self->{'source_data'}->{'sync_file_data'};

    delete $self->{'symlink_cache'};
    for my $source (@source_list) {
        my $sync_file = $self->_convert_path_to_ulc( $self->get_local_cpanelsync_file_name($source) );

        # No action required if local sync file is missing.
        next if ( !-e $sync_file || -z _ );

        # Walk the old file. Unless the file is in exclude or mentioned in one of our new files, mark it for removal via @remove_list
      handle_removed_files_next_syncfile:
        foreach my $line ( split( m{\n}, Cpanel::LoadFile::load($sync_file) ) ) {
            my ( $type, $path, $perm, $extra, $sha ) = split( /===/, $line, 5 );
            next unless ( $type && $path );    # Skip lines which aren't populated.

            $path = $self->_normalize_syncfile_path($path);

            # search for the file normally #
            foreach (@source_list) {

                # NOTE: previous versions of the cpanelsync manifest format did not include cpanelsync.nodecompress, we have to check for that situation here #
                next handle_removed_files_next_syncfile if $syncdata->{$_}->{$path} || ( $syncdata->{$_}->{"$path.cpanelsync.nodecompress"} && $path =~ m/\.(?:bz2|t?gz|xz)$/i );
            }

            my $ulc_path = $self->_convert_path_to_ulc($path);

            # Ignore files we exclude.
            next if $self->is_excluded($ulc_path);

            # If something along the line between syncto and our file is a symlink then this file isn't a candidate for removal
            # Do this check last as its expensive
            next if $self->_symlink_in_path_during_handle_removed_files($ulc_path);

            # Push into remove lists for later processing.
            if ( !-l $ulc_path && -d _ ) {
                push @directories_to_remove, $ulc_path;
            }
            else {
                push @files_to_remove, $ulc_path;
            }
        }
    }
    delete $self->{'symlink_cache'};

    # Delete files and links that don't exist on any sync source
    # Order of deletion doesn't matter
    foreach my $path (@files_to_remove) {
        $self->{'logger'}->info("Removing file/link $path");
        unlink $path;
        if ( -f $path || -l $path ) {
            $self->{'logger'}->warning("Could not unlink '$path': $!");
            $self->{'logger'}->set_need_notify();
        }
    }

    # We must sort the directory list in reverse order by length,
    # so that we delete child directories before parent directories
    @directories_to_remove = sort { length($b) <=> length($a) } @directories_to_remove;

    # Remove the directories.
    foreach my $path (@directories_to_remove) {
        $self->{'logger'}->info("Removing dir $path");
        Cpanel::SafeDir::RM::safermdir($path) || $self->{'logger'}->warning("Could not remove directory '$path': $!");
    }
    return;
}

=item B<fetch_file>

Responsible for downloading a file and validating it's checksum if passed.

=cut

sub fetch_file ( $self, $download_to, $source_path, $file_info ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    # Skip if: The file is already downloaded and it's hash matches $file_info->{'sha'}
    my $file_path_in_ulc = $self->_convert_path_to_ulc($download_to);
    if ( $self->_file_is_already_downloaded_and_matches_digest( $file_path_in_ulc, $file_info ) ) {
        return -1;
    }

    my $cached_hash = $file_info->{'sha'};

    if ( !$file_info->{'nochecksum'} && !$file_info->{'sha'} ) {
        $self->{'logger'}->error("No sha512 digest found!");
        die("No sha512 digest found!");
    }

    # We don't compress .gz files or bz2 files on httpupdate.
    my $uncompress       = ( $source_path !~ m/\.(?:bz2|gz|xz|cpanelsync\.nodecompress)$/ );
    my $real_source_path = $source_path;

    # only exceptions for bz2 files
    if ($uncompress) {
        if ( $source_path =~ m/\.(cpanelsync|static)$/ ) {
            $real_source_path .= '.bz2';
        }
        else {
            $real_source_path .= ".xz";
        }
    }

    # Log we're downloading a file.
    $self->{'logger'}->info("Retrieving and staging $real_source_path");

    my $is_disk_full;

    my $total_attempts = 10;

    # Attempt to download file.
    $self->_create_http_client();
    my $error;

    foreach my $attempt ( 1 .. $total_attempts ) {
        $error = '';
        try {
            local $| = 1;

            my @return = $self->{'http_client'}->request(
                'host'       => $self->{'host'},
                'url'        => $real_source_path,
                'protocol'   => 1,
                'destfile'   => $download_to,
                'signed'     => $file_info->{signed},
                'uncompress' => $uncompress,
            );
            my $ip               = $self->{'http_client'}{'connectedHostAddress'};
            my $last_http_status = $self->{'http_client'}{'last_status'} || 'unknown';

            if ( !$return[-1] ) {
                my $message = "HTTP download returned an error while downloading “$source_path” to “$download_to” (IP: $ip) (HTTP Status:$last_http_status): " . $return[0];
                if ( $attempt % 2 == 0 ) {
                    $message .= "...skipping this mirror.";
                    $self->{'http_client'}->skiphost();
                }
                $self->{'logger'}->error($message);
                die $message;
            }
            elsif ( !-e $download_to ) {
                my $message = "File was unexpectedly missing while downloading “$source_path” to “$download_to” (IP: $ip) (HTTP Status:$last_http_status).";
                if ( $attempt % 2 == 0 ) {
                    $message .= "...skipping this mirror.";
                    $self->{'http_client'}->skiphost();
                }

                $self->{'logger'}->error($message);
                die $message;
            }

            # Validate the checksum on the file, but only if it had a checksum with it (.cpanelsync files don't have one)
            if ( $file_info->{'sha'} ) {
                my $check_hash = $self->get_hash( $download_to, $file_info->{'file'}, $IGNORE_HASH_CACHE );
                if ( $check_hash eq $file_info->{'sha'} ) {
                    $self->{'logger'}->debug("Got file $download_to ok (sha512 matches)");
                }
                else {
                    my $target_info = $self->get_target_info($download_to);

                    unlink $download_to unless $ENV{'UPDATENOW_PRESERVE_FAILED_FILES'};

                    $is_disk_full = $self->is_disk_full() and Carp::confess("The disk is full");

                    my $size = $target_info->{'size'};

                    my $message = "http://$self->{'host'}$real_source_path -> $download_to: Checksum mismatch (actual: $check_hash) (expected: $cached_hash) (size: $size) (IP: $ip) (HTTP Status:$last_http_status) (uncompress_[xz|bz2]: $uncompress)";
                    $self->{'logger'}->error($message);

                    # Try twice per host
                    if ( $attempt % 2 == 0 ) {
                        $message .= "...skipping this mirror.";
                        $self->{'http_client'}->skiphost();
                    }
                    die $message;
                }
            }
        }
        catch {
            $error = $_;
        };

        last if !$error || $is_disk_full || $ENV{'UPDATENOW_PRESERVE_FAILED_FILES'} || $ENV{'UPDATENOW_NO_RETRY'} || $attempt == $total_attempts;

        my $error_as_string = Cpanel::Exception::get_string($error);
        $self->{'logger'}->info("Retrying download of $real_source_path (attempt @{[$attempt+1]}/$total_attempts): $error_as_string");
    }

    if ($error) {
        $self->{'logger'}->set_need_notify();
        die $error;
    }

    return 1;
}

sub _file_is_already_downloaded_and_matches_digest ( $self, $download_to, $file_info ) {

    return 0 if $self->_has_symlinked_parents($download_to);

    # Skip if: The file is already downloaded and it's digest matches
    if ( $file_info->{'sha'} && $self->get_hash( $download_to, $file_info->{'file'}, $USE_HASH_CACHE ) eq $file_info->{'sha'} ) {
        $self->{'logger'}->debug("$download_to already downloaded");
        return 1;
    }

    return 0;
}

sub _df ($path) {

    $path ||= '';
    my @output = `/bin/df -PB1 $path 2>&1`;    ## no critic qw(ProhibitQxAndBackticks)

    return @output;
}

=item B<is_disk_full>

When a checksum failure happens. It could be because we're out of disk space. This subroutine returns 0/1 based on free space.

=cut

sub is_disk_full ($self) {

    my @disk_space = _df( $self->{'syncto'} );

    # df didn't pass. However we can't fail over it here.
    return 0 if ( $? || scalar @disk_space != 2 );

    # df didn't return the POSIX output but we can't fail over it.
    return 0 if ( !length $disk_space[1] || $disk_space[1] !~ m/^\s*\S+\s+\S+\s+\S+\s+([0-9]+)\s/ );

    my $space = $1;

    # The system has less than 100MB free space on 'syncto' (whatever that happens to be.);
    if ( $space < 104857600 ) {    # About 100MB;
        $self->{'logger'}->error( sprintf( "Can not complete downloads. Only %1.02fMB is available on $self->{'syncto'}", $space / 1024 / 1024 ) );
        return 1;
    }

    # syncto seems to have enough space.
    return 0;
}

=item B<stage_directory>

Sets up all directories leading to this file that don't yet exist.
The earliest directory that doesn't exist will have a -cpanelsync on the end of it to denote that it's staged.

=cut

sub stage_directory ( $self, $download_into ) {
    $download_into or Carp::confess('no download provided to stage');

    if ( substr( $download_into, 0, length $self->{'syncto'} ) ne $self->{'syncto'} ) {
        Carp::confess("Cannot stage “$download_into” outside of the syncto path: “$self->{'syncto'}”.");
    }

    # Determine the directory component of the file path.
    my $download_dir = File::Basename::dirname($download_into);
    my $staged_dir   = $download_dir;
    my $last_dir     = '';

    # Check the path we are trying to stage for any symlinks
    # If a symlink is found, then we'll start staging there.
    my ( $symlink_found, @rest_of_path ) = $self->_check_for_symlinked_parents($staged_dir);
    if ($symlink_found) {
        $self->{'staged_directories'}->{ $symlink_found . $self->{'stage_suffix'} } = $symlink_found;
        $staged_dir = File::Spec->catdir( $symlink_found . $self->{'stage_suffix'}, @rest_of_path );
    }
    else {
        return $staged_dir if ( $self->_memorized_stage_dir_exists($staged_dir) );
        my $syncto_length = length( $self->{'syncto'} );

        # Walk upwards till we find a directory that exists.
        while ( !$self->_memorized_stage_dir_exists($staged_dir) ) {
            $last_dir   = File::Basename::basename($staged_dir);
            $staged_dir = File::Basename::dirname($staged_dir);

            # Aborts if stage directory path is shorter than syncto. This is a safety we hope never happens
            length($staged_dir) >= $syncto_length or die( "Unable to calculate stage to directory for $download_into ($syncto_length) (" . length($staged_dir) . ')' );
        }

        # Put the last path back on the list.
        $staged_dir .= '/' . $last_dir;

        # Store the base directory we staged
        $self->{'staged_directories'}->{ $staged_dir . $self->{'stage_suffix'} } = $staged_dir;

        # Put the rest of the path back on by subtr stealing it from the original string.
        $staged_dir .= $self->{'stage_suffix'} . substr( $download_dir, length($staged_dir) );
    }

    # Make the directory.
    if ( !$self->_memorized_stage_dir_exists($staged_dir) ) {
        $self->{'logger'}->info("Creating directory $staged_dir");

        # The '2' here specifies the output level for the Cpanel::Logger::logger() call
        # output level of '2' => STDERR

        Cpanel::SafeDir::MK::safemkdir( $staged_dir, '0700', 2 );
        $self->_rebuild_memorized_stage_dir_exists_cache_and_parents($staged_dir);
    }

    return $staged_dir;
}

sub _memorized_stage_dir_exists ( $self, $path ) {

    return $self->{'memorized_staged_dirs'}{$path} if exists $self->{'memorized_staged_dirs'}{$path};

    return ( $self->{'memorized_staged_dirs'}{$path} = -d $path ? 1 : 0 );
}

sub _memorized_is_symlink ( $self, $path ) {

    return $self->{'memorized_is_symlinks'}{$path} if exists $self->{'memorized_is_symlinks'}{$path};

    return ( $self->{'memorized_is_symlinks'}{$path} = -l $path ? 1 : 0 );
}

sub _rebuild_memorized_stage_dir_exists_cache_and_parents ( $self, $staged_dir ) {
    my $syncto_length = length( $self->{'syncto'} );

    # Walk upwards till we find a reach the syncto location
    while ( length($staged_dir) >= $syncto_length ) {
        $self->{'memorized_staged_dirs'}{$staged_dir} = -d $staged_dir ? 1 : 0;
        $staged_dir = File::Basename::dirname($staged_dir);
    }
    return;
}

sub _has_symlinked_parents ( $self, $path ) {
    my ($base_path) = $self->_check_for_symlinked_parents($path);
    return defined $base_path ? 1 : 0;

}

sub _check_for_symlinked_parents ( $self, $path_to_check ) {

    my @parts_to_check = File::Spec->splitdir( substr( $path_to_check, length $self->{'syncto'} ) );
    return unless @parts_to_check;

    for ( my $i = 0; $i <= $#parts_to_check; $i++ ) {
        my $_path = File::Spec->catdir( $self->{'syncto'}, @parts_to_check[ 0 .. $i ] );

        # Ensure that we never consider the syncto directory a symlink that
        # should be removed.
        next if $_path eq $self->{'syncto'};

        if ( $self->_memorized_is_symlink($_path) ) {
            return ( $_path, @parts_to_check[ $i + 1 .. $#parts_to_check ] );
        }
    }

    return;
}

=item B<stage_file>

Downloads a passed file to the staged directory and keeps track of where it saved it.

=cut

sub stage_file ( $self, $source_path, $download_into, $file_info, $staged_dir ) {    ## no critic qw(Subroutines::ProhibitManyArgs)
    $source_path             or die;                                                     # The URL after hostname for what we want to download (might be minus the .bz2)
    $download_into           or Carp::confess("stage_file requires a download_into");    # The full path to where this file needs to be put ultimatley (not where this sub WILL put it)
    $file_info               or die;                                                     # The cpanelsync hash data.
    length $staged_dir       or die;
    ref $file_info eq 'HASH' or die("file_info not passed as a hash");

    if ( substr( $download_into, 0, length $self->{'syncto'} ) ne $self->{'syncto'} ) {
        Carp::confess("Cannot stage “$download_into” outside of the syncto path: “$self->{'syncto'}”.");
    }

    # Prepend /cpanelsync/11.30.4.5/ to the source_path
    $source_path =~ s{^([^/])}{/$1};                                                     # Assure the passed source_path leads with a slash
    $source_path = $self->{'url'} . $source_path;

    #
    # NOTE: 'staged_files' is a hashref of ARRAYREFS in order to save memory
    #
    # Load the stage dir so _calculate_stage_path_and_temp_file_from_stage_file can cacluate the path
    # ..and mark this file as failed so if we die we can avoid removing it if needed.
    $self->{'staged_files'}->{$download_into}->[$STATE_KEY_POSITION]      = $STATE_FAILED;
    $self->{'staged_files'}->{$download_into}->[$STAGED_DIR_KEY_POSITION] = $staged_dir;

    # Determine what directory we're downloading into.
    my ( $stage_path, $temp_file ) = $self->_calculate_stage_path_and_temp_file_from_stage_file($download_into);

    my $fetched = $self->fetch_file( $stage_path, $source_path, $file_info );

    if ( defined $fetched && $fetched == -1 ) {

        # when the file is not fetched ( without raising a die )
        #   this means the target already exists, we are not going to use a temporary staged file
        # permissions are going to be fixed later by validate_file_permissions if needed
        delete $self->{'staged_files'}->{$download_into};
        return;
    }

    $self->{'staged_files'}->{$download_into}->[$STATE_KEY_POSITION] = $STATE_OK;

    my $dest_file_info = $self->get_target_info($download_into);
    if ( !$dest_file_info->{'exists'} ) {
        $dest_file_info = { 'uid' => -1, 'gid' => -1 };
    }

    # Fix the permissions on the downloaded file
    # setup new file's mode
    if ( $self->is_excluded_chmod($download_into) && $dest_file_info->{'exists'} ) {
        my $original_mode = sprintf( '%04o', ( $dest_file_info->{'perm'} & 07777 ) );
        $self->{'logger'}->warning("$download_into is excluded from chmod so the local mode $original_mode will be preserved.");
        $self->chown( $dest_file_info->{'uid'}, $dest_file_info->{'gid'}, $stage_path );
        $self->chmod( $original_mode, $self->get_target_info($stage_path), 1 );
        $file_info->{'perm'} = $original_mode;    # Protect from validate_file_permissions (which should be honoring excludes anyways but still...)
    }
    else {
        $self->{'logger'}->debug("$stage_path set from cpanelsync mode $file_info->{'perm'}");
        $self->chown( $dest_file_info->{'uid'}, $dest_file_info->{'gid'}, $stage_path );
        $self->chmod( $file_info->{'perm'}, $self->get_target_info($stage_path) );
    }
    return $stage_path;
}

sub get_staged_file ( $self, $file ) {
    $file or die;

    if ( !$self->{'staged_files'}->{$file} ) {
        $file = $self->_convert_path_to_staging($file);
    }

    return if ( !$self->{'staged_files'}->{$file} || !$self->{'staged_files'}->{$file}->[$STATE_KEY_POSITION] );

    my ( $stage_path, $temp_file ) = $self->_calculate_stage_path_and_temp_file_from_stage_file($file);

    return $stage_path;
}

# Calculate the full path to a cpanelsync source file stored locally.
sub get_local_cpanelsync_file_name ( $self, $source ) {
    $source or die("no source provided");

    my $local_cpanelsync_file = $source;
    $local_cpanelsync_file =~ s{/+}{__forward_slash__}g;
    return "$self->{'syncto'}/$self->{'sync_basename'}_$local_cpanelsync_file";
}

sub stage_cpanelsync_files ($self) {

    return $self if $self->{'already_ran_stage_cpanelsync_files'};

    # Download the .cpanelsync files from all the sources we'll be syncing. Store them locally.
    for my $source ( $self->get_source_list() ) {
        my $dest_file   = $self->get_local_cpanelsync_file_name($source);
        my $staging_dir = $self->stage_directory($dest_file);
        $self->stage_file( "/$source/$self->{'sync_basename'}", $dest_file, { 'perm' => '0644', 'signed' => 1, 'nochecksum' => 1 }, $staging_dir );
    }

    $self->{'already_ran_stage_cpanelsync_files'} = 1;
    return $self;
}

=item B<stage>

Downloads all files which need to be downloaded to a temp loation with the following steps:

=over

=item *

1. Download cpanelsync files to a temp location.

=item *

2. Parse cpanelsync files into memory.

=item *

3. Download files if they are not excluded and the checksum on the files don't match

=back

=cut

sub stage ( $self, %opts ) {

    $self->{'logger'}->debug( 'Starting at ' . time() );

    if ( !-d $self->{'syncto'} ) {
        Cpanel::SafeDir::MK::safemkdir( $self->{'syncto'}, 0755 );
        $self->{'logger'}->info("Created base directory: $self->{'syncto'}");
    }

    $self->{'logger'}->debug('Initializing hash cache');
    $self->init_current_digest_cache();

    $self->{'logger'}->debug('Downloading and reading cpanelsync files.');
    $self->stage_cpanelsync_files();
    $self->parse_new_cpanelsync_files();

    # on fresh install we skip the download (use a tarball),
    #   but still want to use the tree for logic from the commit
    return 1 if $opts{'no_download'};

    my %files_to_stage_by_child = ();
    my $child_num               = 1;

    my $max_num_of_sync_children_this_system_can_handle = $self->calculate_max_sync_children();

    # Stage all of the files we need to download.
    for my $source ( $self->get_source_list() ) {
        $self->{'logger'}->info("Staging files for $source");
        my $cpanelsync_data = $self->{'source_data'}->{'sync_file_data'}->{$source};

        # We only need to stage files
        for my $path ( grep { $cpanelsync_data->{$_}{'type'} eq 'f' } keys %$cpanelsync_data ) {

            # some files are not going to be decompressed, we want to check them without this directive in the name #
            my $path_modified = $path;
            substr( $path_modified, -24, 24, '' ) if substr( $path_modified, -24 ) eq '.cpanelsync.nodecompress';

            my $file_info_in_ulc = $self->get_target_info( $self->_convert_path_to_ulc($path_modified) );

            # Don't download excluded files.
            if ( $self->is_excluded( $file_info_in_ulc->{'path'} ) ) {
                $self->{'logger'}->warning("Excluding from sync: '$file_info_in_ulc->{'path'}'");
                next;
            }

            if (   $cpanelsync_data->{$path}->{'sha'}
                && $self->get_hash( $file_info_in_ulc->{'path'}, $cpanelsync_data->{$path}->{'file'}, $USE_HASH_CACHE, $file_info_in_ulc ) eq $cpanelsync_data->{$path}->{'sha'}
                && !$self->_has_symlinked_parents($path_modified) ) {
                $self->{'get_target_info_cache_hash_checked'}{ $file_info_in_ulc->{'path'} } = $file_info_in_ulc;
                next;
            }

            # Download the file to a temp location and keep track of where you put it.
            my $download_from = $cpanelsync_data->{$path}->{'file'};
            $download_from =~ s{^\./}{};    # Strip ./ from the front of file paths.
            $download_from = "/$source/$download_from";

            if ( $child_num > $max_num_of_sync_children_this_system_can_handle ) { $child_num = 1; }

            # Determine what directory we're downloading into.
            my $staged_dir = $self->stage_directory($path_modified);

            push @{ $files_to_stage_by_child{ $child_num++ } }, [ $download_from, $path_modified, $cpanelsync_data->{$path}, $staged_dir ];
        }
    }

    return $self->download_files( \%files_to_stage_by_child );
}

sub download_files ( $self, $files_to_stage_by_child_ref ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    $self->_load_best_available_serializer();

    $self->_create_sync_children($files_to_stage_by_child_ref);

    $self->_wait_load_results_from_sync_children();

    return 1;
}

sub _wait_load_results_from_sync_children ($self) {

    while ( scalar keys %{ $self->{'sync_children'} } ) {
        my $child_pid;
        my @pids = keys %{ $self->{'sync_children'} };
        foreach my $pid (@pids) {
            $child_pid = waitpid( $pid, 1 );
            if ( $child_pid == -1 ) {
                delete $self->{'sync_children'}{$pid};
                next;
            }
            elsif ( $child_pid == 0 ) {
                next;
            }
            else {
                last;
            }
        }

        if ( $child_pid && $self->{'sync_children'}{$child_pid} ) {

            if ( $? != 0 ) {
                $self->{'logger'}->error( "Sync child $child_pid exited with signal: " . ( $? & 127 ) . " and code: " . ( $? >> 8 ) );
                $self->{'logger'}->set_need_notify();
            }
            else {
                $self->{'logger'}->info("Sync child $child_pid exited cleanly.");
            }

            my $temp_file = delete $self->{'sync_children'}{$child_pid};
            if ( open( my $fh, '<', $temp_file ) ) {
                my ( $child_data, $error );

                try {
                    local $/;
                    $child_data = ( Cpanel::JSON::Load( readline($fh) ) )[0];
                }
                catch {
                    $error = $_;
                };
                if ($error) {
                    my $error_as_string = Cpanel::Exception::get_string($error);
                    my $error_message   = "Failed to deserialize staged_files and digest_lookup from: $temp_file because of an error: $error_as_string";
                    $self->{'logger'}->error($error_message);
                    $self->{'logger'}->set_need_notify();
                    die $error_message;
                }

                $self->{'staged_files'} = {
                    %{ $self->{'staged_files'} },
                    %{ $child_data->{'staged_files'} }
                };
                $self->{'digest_lookup'} = {
                    %{ $self->{'digest_lookup'} },
                    %{ $child_data->{'digest_lookup'} }
                };

                close($fh);
            }
            else {
                die "Failed to read back staged_files and digest_lookup from: $temp_file: $!";
            }
        }
        else {
            select( undef, undef, undef, 0.025 );
        }
    }

    delete $self->{'sync_children_temp_obj'};
    delete $self->{'sync_children'};
    return 1;
}

sub _create_sync_children ( $self, $files_to_stage_by_child_ref ) {    ## no critic qw(Subroutines::ProhibitManyArgs)

    $self->{'sync_children_temp_obj'} = Cpanel::TempFile->new();
    $self->{'sync_children'}          = {};
    $self->{'http_client'}            = undef;

    my $NUM_SYNC_CHILDREN = scalar keys %{$files_to_stage_by_child_ref};
    $self->_create_http_client() if $NUM_SYNC_CHILDREN;
    for my $child_num ( 1 .. $NUM_SYNC_CHILDREN ) {
        my $temp_file = $self->{'sync_children_temp_obj'}->file();
        $self->{'logger'}->info("Child: $child_num: Stage File: $temp_file");

        if ( my $child_pid = fork() ) {
            $self->{'sync_children'}{$child_pid} = $temp_file;
            $self->{'logger'}->info("Child $child_pid created to stage files.");
        }
        elsif ( defined $child_pid ) {

            my $files_ref = delete $files_to_stage_by_child_ref->{$child_num};
            undef $files_to_stage_by_child_ref;

            # $files_ref are the args for stage_file()
            # [0] - $source_path
            # [1] - $download_info
            # [2] - $file_info
            # [3] - $staged_dir
            my %files_to_stage_this_child = map { $_->[2]->{'file'} => 1 } @{$files_ref};
            delete @{ $self->{'digest_lookup'} }{ grep { !$files_to_stage_this_child{$_} } keys %{ $self->{'digest_lookup'} } };
            %files_to_stage_this_child = ();

            foreach my $file_ref ( @{$files_ref} ) {
                my $error;
                try {
                    $self->stage_file( @{$file_ref} );
                }
                catch {    # Its possible to get EIO when calculating the MD5 of the file
                    $error = $_;
                };
                if ($error) {
                    my $error_as_string = Cpanel::Exception::get_string($error);
                    $self->{'logger'}->error("Unable to stage file from $file_ref->[0] => $file_ref->[1]: $error_as_string");
                    $self->{'logger'}->set_need_notify();
                    exit(1);
                }
            }

            my $error;
            try {
                Cpanel::FileUtils::Write::overwrite( $temp_file, Cpanel::JSON::Dump( { 'staged_files' => $self->{'staged_files'}, 'digest_lookup' => $self->{'digest_lookup'} } ), 0600 );    #
            }
            catch {
                $error = $_;
            };
            if ($error) {
                my $error_as_string = Cpanel::Exception::get_string($error);
                $self->{'logger'}->error("Unable write stage file data to: $temp_file: $error_as_string");
                $self->{'logger'}->set_need_notify();
                exit(1);
            }

            exit(1) if $self->{'logger'}->get_need_notify();
            exit(0);
        }
        else {
            die "Failed to fork(): $!";
        }
    }
    return 1;

}

sub _load_best_available_serializer ($self) {

    foreach my $modules ( [ 'JSON::XS', 'Cpanel::JSON' ], [ 'YAML::Syck', 'Cpanel::YAML' ] ) {
        my $error;

        # Might not be available at this point.
        try {
            Cpanel::LoadModule::load_perl_module($_) for @$modules;
        }
        catch {
            $error = $_;
        };
        last if !$error;
    }

    return 1;
}

sub commit ($self) {

    delete $self->{'memorized_staged_dirs'};
    delete $self->{'memorized_is_symlinks'};

    Cpanel::SafeDir::MK::safemkdir( $self->{'syncto'} ) if ( !-d $self->{'syncto'} );

    # Foreach 'source' passed into new.
    $self->{'logger'}->debug('  Remove pre-existing files that are not found in any data source');
    $self->handle_removed_files();

    $self->{'logger'}->debug('  Move staged directories into place.');
    $self->commit_directories();

    $self->{'logger'}->debug('  Move staged files into place.');
    $self->commit_files();

    $self->{'logger'}->debug('  Put Symlinks in place.');
    $self->handle_symlinks();

    $self->{'logger'}->debug('  Validate all permissions');
    $self->validate_file_permissions();

    $self->{'logger'}->debug('  Saving updated digest cache');
    $self->save_updated_digest_data();

    $self->{'logger'}->debug('  Making .cpanelsync.new file list');
    $self->create_dot_new_file();

    $self->{'logger'}->debug( "  Ending at " . time() );
    return 1;
}

# a trimmed-down version of script() that only downloads updatenow.static to a temp file
# So we can run the *target* version's update procedure, rather than the current version's procedure
sub sync_updatenow_static ( $self, $skip_signature_check = 0 ) {

    my $dir = $self->{'syncto'} . '/scripts';

    # Need to do this here, in case the staging dir has been changed
    # between upgraded and the base path no longer exists.
    if ( !-d $self->{'syncto'} ) {
        Cpanel::SafeDir::MK::safemkdir( $self->{'syncto'}, 0711 );
        Cpanel::SafeDir::MK::safemkdir( $dir,              0755 );
    }

    my $target = $self->{'syncto'} . '/scripts/updatenow.static';
    $self->stage_file( "/cpanel/scripts/updatenow.static", $target, { 'file' => './scripts/updatenow.static', 'perm' => '0700', 'signed' => int( !$skip_signature_check ), 'nochecksum' => 1 }, $dir );

    return $self->get_staged_file($target);
}

sub _calculate_stage_path_and_temp_file_from_stage_file ( $self, $stage_file ) {

    Carp::confess("$stage_file is not staged") if ref $self->{'staged_files'}->{$stage_file} ne 'ARRAY';

    my $staged_dir = $self->{'staged_files'}->{$stage_file}->[$STAGED_DIR_KEY_POSITION] or Carp::confess("$stage_file does not have a staged_dir value.");

    return ( $staged_dir . '/' . File::Basename::basename($stage_file) . $self->{'stage_suffix'}, $stage_file . $self->{'stage_suffix'} );
}

sub DESTROY ($self) {

    return if $self->{'master_pid'} && $self->{'master_pid'} != $$;

    # Don't delete anything if nothing was staged.
    return unless ( ( $self->{'staged_files'} && %{ $self->{'staged_files'} } ) or ( $self->{'staged_directories'} && %{ $self->{'staged_directories'} } ) );

    $self->{'logger'}->info( "Removing staged files and directories for " . join( ', ', @{ $self->{'source'} || () } ) );
    my %dirs_to_keep;
    foreach my $stage_file ( keys %{ $self->{'staged_files'} } ) {
        my ( $stage_path, $temp_file ) = $self->_calculate_stage_path_and_temp_file_from_stage_file($stage_file);

        # Calculate the staging info from the path only when we need it
        # instead of storing it in a hash which uses too much memory
        if ( $self->{'staged_files'}{$stage_file}->[$STATE_KEY_POSITION] == $STATE_FAILED && $ENV{'UPDATENOW_PRESERVE_FAILED_FILES'} ) {
            $self->{'logger'}->info("Skipping removal of file $stage_file as requested");
            foreach my $file ( $temp_file, $stage_path ) {
                $file =~ m{^(.*)/[^/]+$};
                $dirs_to_keep{$1} = 1;
            }
            next;
        }

        if ( -e $temp_file ) {
            unlink $temp_file;
        }

        if ( $temp_file ne $stage_path && -e $stage_path ) {
            unlink $stage_path;
        }
    }

    foreach my $stage_dir ( keys %{ $self->{'staged_directories'} } ) {
        if ( $dirs_to_keep{$stage_dir} ) {
            $self->{'logger'}->info("Skipping removal of directory $stage_dir as requested");
            next;
        }

        if ( -e $stage_dir ) {
            system( '/bin/rm', '-rf', '--', $stage_dir );
        }
    }

    return;
}

=back

=cut

1;
