package Whostmgr::Transfers::ArchiveManager;

# cpanel - Whostmgr/Transfers/ArchiveManager.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent 'Cpanel::Destruct::DestroyDetector';

# RR Audit: FG

use Try::Tiny;

use Cpanel::CPAN::IO::Callback::Write ();
use Cpanel::Exception                 ();
use Cpanel::Config::LoadCpUserFile    ();
use Cpanel::Autodie                   ();

use Cwd ();

use Cpanel::Archive::Utils      ();
use Cpanel::ArrayFunc           ();
use Cpanel::Carp                ();
use Cpanel::DiskCheck           ();
use Cpanel::FileUtils::Dir      ();
use Cpanel::FileUtils::Read     ();
use Cpanel::LinkedNode::Archive ();
use Cpanel::LoadFile            ();
use Cpanel::Locale              ();
use Cpanel::Logger              ();
use Cpanel::Rand                ();
use Cpanel::SafeRun::Object     ();
use Cpanel::Tar                 ();
use Cpanel::Validate::Username  ();

use Whostmgr::Transfers::Utils::WorkerNodesObj ();

#TODO: This module’s error messages should be translated.

my $logger = Cpanel::Logger->new();

our $MAX_CPUSER_FILE_SIZE = 1024**2;    # case 113333: 1 MiB
our $EXTRACT_TIMEOUT      = 43200;      # 12 hours -- case 106653

my $locale;

sub _locale {
    return $locale ||= Cpanel::Locale->get_handle();
}

sub new {
    my ( $class, %OPTS ) = @_;

    if ( !ref( $OPTS{'utils'} ) || !$OPTS{'utils'}->isa('Whostmgr::Transfers::Utils') ) {
        die "The required parameter 'utils' needs to be of type 'Whostmgr::Transfers::Utils'.";
    }

    my $tarcfg = Cpanel::Tar::load_tarcfg();

    my ( $status, $message ) = Cpanel::Tar::checkperm();
    if ( !$status ) {
        $logger->warn("Could not find working tar: $message");
        die "Could not find working tar: $message";
    }

    return bless {
        'tarcfg'        => $tarcfg,
        '_pid'          => $$,
        '_utils'        => $OPTS{'utils'},
        'skipped_items' => [],
        'messages'      => [],
        'flags'         => ( $OPTS{'flags'} || {} ),
    }, $class;

}

sub utils {
    my ($self) = @_;

    return $self->{'_utils'};
}

sub extracted {
    my ($self) = @_;

    return $self->{'_extracted'} || 0;
}

#Returns two-arg format (with a 3rd arg on success).
sub safely_prepare_package_for_restore {
    my ( $self, $path ) = @_;

    my $path_is_dir = -d $path ? 1 : 0;
    if ( !length $path ) {
        return ( 0, "The required parameter 'path' is missing." );
    }
    elsif ( $path !~ m{^/} ) {
        return ( 0, "Only absolute paths may be restored; “$path” is a relative path." );
    }
    elsif ( -l $path ) {
        return ( 0, "The archive may not be a symlink." );
    }
    elsif ( !$path_is_dir && !chmod( 0600, $path ) ) {
        return ( 0, "Failed to chmod 0600 $path: $!" );
    }

    my @path     = ( split( /\/+/, $path ) );
    my $filename = pop(@path);
    my $file_dir = join( '/', @path ) || '/';    # Yes, they put archives in /

    my $temp_dir = Cpanel::Rand::get_tmp_dir_by_name("$file_dir/cpanelpkgrestore.TMP");
    if ( !-d $temp_dir ) {
        return ( 0, "Failed to create a temporary directory to extract the archive" );
    }
    $self->{'_temp_extract_dir'} = $temp_dir;

    if ( !chmod( 0700, $temp_dir ) ) {
        return ( 0, "Failed to chmod() 0700 $temp_dir: $!" );
    }

    my $archive_dir = "$temp_dir/unsafe_to_read_archive";
    my $homedir_dir = "$temp_dir/unsafe_to_read_homedir";

    if ( !mkdir( $archive_dir, 0700 ) ) {
        return ( 0, "Could not mkdir() $archive_dir: $!" );
    }
    if ( !mkdir( $homedir_dir, 0700 ) ) {
        return ( 0, "Could not mkdir() $homedir_dir: $!" );
    }

    my $ignore_disk_space = 0;

    # Case 176937 restorepkg --force ignore disk space checks.
    if (   exists $self->{'_utils'}
        && exists $self->{'_utils'}->{'flags'}
        && exists $self->{'_utils'}->{'flags'}->{'ignore_disk_space'} ) {
        if ( exists $self->{'_utils'}->{'flags'} ) {
            if ( exists $self->{'_utils'}->{'flags'}->{'ignore_disk_space'} ) {
                $ignore_disk_space = $self->{'_utils'}->{'flags'}->{'ignore_disk_space'};
            }
        }
    }

    my ( $disk_ok, $disk_msg );

    if ( !$ignore_disk_space ) {
        ( $disk_ok, $disk_msg ) = Cpanel::DiskCheck::target_has_enough_free_space_to_fit_source(
            'source'         => $path,
            'target'         => $archive_dir,
            'output_coderef' => sub {
                my ($str) = @_;
                $self->{'_utils'}->out($str);
            }
        );
        return ( $disk_ok, $disk_msg ) if !$disk_ok;
    }
    else {
        ( $disk_ok, $disk_msg ) = ( 1, "successful" );
    }

    if ($path_is_dir) {
        my $run = Cpanel::SafeRun::Object->new(
            program => '/bin/cp',
            timeout => $EXTRACT_TIMEOUT,                                        # case 108381
            args    => [ '--archive', '--force', '--', $path, $archive_dir ],
        );
        return ( 0, $run->stderr() . $run->autopsy() ) if $run->CHILD_ERROR();
    }
    else {
        my ( $tarstatus, $tarstatusmsg ) = $self->_extract_tarball_to_dir( $path, $archive_dir );

        if ( !$tarstatus ) { return ( $tarstatus, $tarstatusmsg ); }
    }

    # Normalize the paths to be
    # TEMP/unsafe_to_read_homedir
    # TEMP/unsafe_to_read_archive/contents
    my ( $normalizestatus, $normalizestatusmsg ) = $self->_normalize_extracted_archive();
    if ( !$normalizestatus ) { return ( $normalizestatus, $normalizestatusmsg ); }

    # Move away the homedir portion as we need to perserve the permissions here
    my ( $moveawaystatus, $moveawaystatusmsg ) = $self->_move_away_homedir_from_unsafe_to_read_archive($temp_dir);
    if ( !$moveawaystatus ) { return ( $moveawaystatus, $moveawaystatusmsg ); }

    # Now that we have moved away the homedir so we do not alter the permissions
    # we can remove any symlinks and malicious permissions.
    my ( $permsafestatus, $permsafestatusmsg ) = $self->_make_extracted_archive_safe_to_read($temp_dir);
    if ( !$permsafestatus ) { return ( $permsafestatus, $permsafestatusmsg ); }

    # system 'find', $temp_dir;
    # After _make_extracted_archive_safe_to_read we have
    # TEMP/unsafe_to_read_homedir
    # TEMP/safe_to_read_archive/contents

    $self->{'_extracted'} = 1;

    return ( 1, _locale()->maketext("The system successfully prepared the archive for restoration."), $temp_dir );
}

sub trusted_source_root_directory {
    my ($self) = @_;

    my $temp_dir = $self->{'_temp_extract_dir'} || Carp::confess("'_temp_extract_dir' is missing from the object");

    return $temp_dir . '/safe_to_read_archive';
}

sub trusted_archive_contents_dir {
    my ($self) = @_;

    return $self->trusted_source_root_directory() . '/contents';
}

# Returns the path for the subarchive root that corresponds to the
# given $worker_type. For example, if $worker_type is Mail, this gives
# the root of the archive’s Mail-worker subarchive.
#
sub trusted_archive_contents_dir_for_worker ( $self, $worker_type ) {
    my $main_extractdir = $self->trusted_archive_contents_dir();

    my $worker_obj = $self->{'_worker_obj'} ||= Whostmgr::Transfers::Utils::WorkerNodesObj->new($main_extractdir);

    my $worker_dir_path;

    if ( my $worker_alias = $worker_obj->get_type_alias($worker_type) ) {
        my $path = "$main_extractdir/" . Cpanel::LinkedNode::Archive::subarchive_relative_root($worker_alias);

        if ( Cpanel::Autodie::exists_nofollow($path) ) {

            # A sanity check:
            if ( !-d _ ) {
                die "“$path” should be a directory but isn’t!";
            }

            $worker_dir_path = $path;
        }
        else {
            warn "Archive’s worker index records a $worker_type worker (alias=$worker_alias) but lacks its subarchive ($path).\n";
        }
    }

    return $worker_dir_path;
}

sub unsafe_to_read_source_homedir {
    my ($self) = @_;

    my $temp_dir = $self->{'_temp_extract_dir'} || Carp::confess("'_temp_extract_dir' is missing from the object");

    # Will contain 'homedir' or 'homedir.tar'

    return $temp_dir . '/unsafe_to_read_homedir';
}

sub _looks_like_cpuser_file {
    my ( $self, $path ) = @_;

    local $!;

    return ( 1, 0 ) if !-f $path;

    my $size = -s _;
    if ( $size > $MAX_CPUSER_FILE_SIZE ) {
        return ( 0, "The file “$path” is too big ($size bytes) be a legitimate cpuser file!" );
    }

    my ( $is_cpuser, $err );

    try {
        Cpanel::FileUtils::Read::for_each_line(
            $path,
            sub {
                if (m<\A(?:DNS|USER)=>) {
                    $is_cpuser = 1;
                    shift()->stop();
                }
            },
        );
    }
    catch { $err = $_->to_string() };

    return ( 0, $err ) if $err;

    return ( 1, $is_cpuser ? 1 : 0 );
}

#NOTE: Two-part return; note that (1,<false>) just means that we determined,
#successfully, that there is no archive payload here.
#An error case, (0, undef), means that we
#encountered a problem in determining whether there's an archive payload here.
#
sub _look_for_cpuser_file_in_potential_payload_dir {
    my ( $self, $payload_dir ) = @_;

    die Cpanel::Carp::safe_longmess("This method should never be called twice!") if $self->{'_username'};

    my $cp_dir = "$payload_dir/cp";

    #There definitely is not a payload in the passed-in directory
    #if there is no $payload_dir/cp directory.
    #
    #NOTE: We already checked that $payload_dir is not a symlink.
    #
    return ( 1, undef ) if !-d $cp_dir;

    local $!;

    opendir( my $dh, $cp_dir ) or do {
        return ( 0, "_look_for_cpuser_file_in_potential_payload_dir: failed to opendir() $cp_dir: $!" );
    };

    my $the_only_node_name;
    while ( my $dir_entry = readdir $dh ) {
        next if ( $dir_entry eq '.' || $dir_entry eq '..' );

        # node_path might be a cpanel user file
        #
        my $node_path = "$cp_dir/$dir_entry";

        my ( $no_link, $link_err ) = $self->_ensure_not_a_symlink($node_path);
        return ( 0, $link_err ) if !$no_link;

        if ( Cpanel::Validate::Username::is_valid($dir_entry) ) {

            #There can only be one file in the cp/ directory for this
            #to be a valid cpmove / backup file.
            #
            #Don't error on this since we'll just handle it by looking elsewhere
            #for a valid cp/ directory since this directory has more than one file.
            #
            # We return true because we want to keep looking
            return ( 1, undef ) if length $the_only_node_name;

            $the_only_node_name = $dir_entry;
        }
    }

    # If we only found one file, we test it to see if it
    # looks like a cpuser file.
    if ($the_only_node_name) {
        my ( $ok, $is_cpuser ) = $self->_looks_like_cpuser_file("$cp_dir/$the_only_node_name");
        return ( 0, $is_cpuser ) if !$ok;

        # Successful find of a cpuser file here
        if ($is_cpuser) {
            $self->{'_utils'}->{'original_username'} = $self->{'_username'} = $the_only_node_name;
            return ( 1, $the_only_node_name );
        }
    }

    # We return true because we want to keep looking
    # since we have not found a valid cpuser file yet
    return ( 1, undef );
}

sub _ensure_not_a_symlink {
    my ( $self, $node_path ) = @_;

    if ( -l $node_path ) {
        my $relative_path = $node_path;
        $relative_path =~ s[\A\Q$self->{'_temp_extract_dir'}\E/][];

        return ( 0, "There is an inappropriate symbolic link ($relative_path) in the extracted archive." );
    }

    return 1;
}

#Two-part return, except success also returns the name of the
#$cp/username file as a third item.
sub _find_payload_in_extracted_dir {
    my ($self) = @_;

    my $temp_dir = $self->{'_temp_extract_dir'} || Carp::confess("'_temp_extract_dir' is missing from the object");

    my $archive_dir = "$temp_dir/unsafe_to_read_archive";

    #First look for the cp/$username file in the root dir first;
    #if found here, then we know the payload is in the archive's root.
    my ( $check_ok, $olduser_name ) = $self->_look_for_cpuser_file_in_potential_payload_dir($archive_dir);
    return ( 0, $olduser_name ) if !$check_ok;

    my $payload_dir;

    if ( length $olduser_name ) {

        # We have found a cpusers file in the root dir's cp/ dir
        # so we set the payload_dir to an empty string since it is at
        # the root dir.
        #
        $payload_dir = q<>;
    }
    else {
        #Ok, the payload wasn't in the archive's root.
        #Now look for it in a directory (one-deep) of the archive.

        opendir( my $dh, $archive_dir ) or do {
            return ( 0, "_find_payload_in_extracted_dir: failed to opendir() $temp_dir: $!" );
        };

        while ( my $dir_entry = readdir($dh) ) {
            next if ( $dir_entry eq '.' || $dir_entry eq '..' );

            my $node_path = "$archive_dir/$dir_entry";

            my ( $no_link, $link_err ) = $self->_ensure_not_a_symlink($node_path);
            return ( 0, $link_err ) if !$no_link;

            if ( !length $olduser_name ) {
                ( my $ok, $olduser_name ) = $self->_look_for_cpuser_file_in_potential_payload_dir($node_path);
                return ( 0, $olduser_name ) if !$ok;

                if ( length $olduser_name ) {
                    $payload_dir = $dir_entry;

                    # We have found the root of the archive, however we still need to continue
                    # here in order to make sure there are no symlinks in the archive
                    # in order to comply with the security policy.
                }
            }
        }

        #TODO: Once Perl's readdir/$! bug is worked out (Perl 5.20? 5.22?),
        #check for $! errors here.

        closedir $dh or do {
            $logger->warn("The system failed to close the directory “$archive_dir” because of an error: $!");
        };
    }

    return ( 1, $payload_dir, $olduser_name );
}

#Returns two-arg format.
sub _normalize_extracted_archive {
    my ($self) = @_;

    my $temp_dir = $self->{'_temp_extract_dir'} || Carp::confess("'_temp_extract_dir' is missing from the object");

    my ( $ok, $payload_dir, $olduser_name ) = $self->_find_payload_in_extracted_dir();
    return ( 0, $payload_dir ) if !$ok;

    if ( !defined $payload_dir ) {
        return ( 0, "_normalize_extracted_archive: The extracted archive does not contain a valid cpanel user file." );
    }

    my $archive_dir = "$temp_dir/unsafe_to_read_archive";

    if ( length $payload_dir ) {
        $self->{'_utils'}->out( _locale()->maketext( 'This archive’s payload appears to be in the archive’s “[_1]” directory.', $payload_dir ) );

        if ( !rename( "$archive_dir/$payload_dir", "$archive_dir/contents" ) ) {
            return ( 0, "_normalize_extracted_archive: Could not rename “$payload_dir” to “contents” inside “unsafe_to_read_archive”: $!" );
        }
    }
    else {
        $self->{'_utils'}->out( _locale()->maketext('This archive’s payload appears to be at the archive’s root level.') );

        if ( !rename( "$temp_dir/unsafe_to_read_archive", "$temp_dir/contents" ) ) {
            return ( 0, "_normalize_extracted_archive: Could not rename “unsafe_to_read_archive” to “contents”: $!" );
        }
        if ( !mkdir( "$temp_dir/unsafe_to_read_archive", 0700 ) ) {
            return ( 0, "_normalize_extracted_archive: Could not mkdir() “unsafe_to_read_archive” (after renaming original): $!" );
        }
        if ( !rename( "$temp_dir/contents", "$temp_dir/unsafe_to_read_archive/contents" ) ) {
            return ( 0, "_normalize_extracted_archive: Could not rename “contents” to “unsafe_to_read_archive/contents”: $!" );
        }
    }

    return ( 1, "_normalize_extracted_archive: normalized archive contents" );
}

#Returns two-arg format.
sub _make_extracted_archive_safe_to_read {
    my ($self) = @_;

    my $temp_dir = $self->{'_temp_extract_dir'} || Carp::confess("'_temp_extract_dir' is missing from the object");

    my $unsafe_to_read_path = "$temp_dir/unsafe_to_read_archive/contents";

    # These duplicate some of the logic found authoritatively in
    # Cpanel::LinkedNode::Archive.
    my $worker_pkgacct_path_slash = "$unsafe_to_read_path/worker_pkgacct/";
    my $whitelist_re              = qr<\A\Q$worker_pkgacct_path_slash\E [^/]+/homedir\z>x;

    my ( $status, $statusmsg, $ret ) = Cpanel::Archive::Utils::sanitize_extraction_target(
        "$temp_dir/unsafe_to_read_archive/contents",

        preprocess => sub {
            return @_ if 0 != rindex( $File::Find::dir, $worker_pkgacct_path_slash, 0 );

            return ( $File::Find::dir =~ $whitelist_re ? () : @_ );
        },
    );

    foreach my $unlinked ( @{ $ret->{'unlinked'} } ) {
        $self->{'_utils'}->add_skipped_item( _locale()->maketext( 'The system unlinked “[_1]” because it is neither a regular file nor a directory.', $unlinked ) );
    }
    foreach my $modified ( @{ $ret->{'modified'} } ) {
        $self->{'_utils'}->warn( _locale()->maketext( 'The system sanitized permissions on “[_1]”.', $modified ) );
    }

    return ( $status, $statusmsg ) if !$status;

    if ( !rename( "$temp_dir/unsafe_to_read_archive", "$temp_dir/safe_to_read_archive" ) ) {
        return ( 0, "Failed to rename “unsafe_to_read_archive” to “safe_to_read_archive”: $!" );
    }

    return ( 1, 'Make permissions safe to read' );
}

#Returns two-arg format.
sub _move_away_homedir_from_unsafe_to_read_archive {
    my ($self) = @_;

    my $temp_dir = $self->{'_temp_extract_dir'} || Carp::confess("'_temp_extract_dir' is missing from the object");

    my $contents_dir = "$temp_dir/unsafe_to_read_archive/contents";

    my $found_homedir = 0;

    if ( -l "$contents_dir/homedir.tar" ) {
        return ( 0, "“homedir.tar” may not be a symbolic link." );
    }
    elsif ( -s _ ) {
        $found_homedir++;

        if ( !rename( "$contents_dir/homedir.tar", "$temp_dir/unsafe_to_read_homedir/homedir.tar" ) ) {
            return ( 0, "Failed to move “homedir.tar” to the “unsafe_to_read_homedir” directory: $!" );
        }
    }

    if ( -l "$contents_dir/homedir" ) {
        return ( 0, "“homedir” may not be a symbolic link." );
    }
    elsif ( -e _ ) {
        $found_homedir++;

        if ( !rename( "$contents_dir/homedir", "$temp_dir/unsafe_to_read_homedir/homedir" ) ) {
            return ( 0, "Failed to move “homedir” to the “unsafe_to_read_homedir” directory: $!" );
        }
    }

    if ( !$found_homedir ) {
        #
        # cpmove created with --skiphomedir
        #
        return ( 1, "Warning: “homedir” and homedir.tar are both missing from this restore file." );
    }

    return ( 1, "Moved away homedir" );
}

#Returns two-arg format.
sub _extract_tarball_to_dir {    ## no critic (RequireArgUnpacking)
    my ( $self, $file, $dir ) = (@_);

    my $tarcfg = $self->{'tarcfg'};

    my $compress_flag = ( $file =~ m/\.bz2$/ ? '--bzip2' : $file =~ m/\.gz$/ ? '--use-compress-program=/usr/local/cpanel/bin/gzip-wrapper' : '' );

    my ( $combined_output, $stdout, $stderr ) = (q<>) x 3;

    local $ENV{'LANG'} = 'C';    # avoid before_exec as it prevents fastspawn

    my $run = Cpanel::SafeRun::Object->new(
        program => $tarcfg->{'bin'},
        timeout => $EXTRACT_TIMEOUT,
        args    => [
            $tarcfg->{'no_same_owner'},
            ( $compress_flag || () ),
            '--preserve-permissions',
            '--extract',
            '--directory' => $dir,
            '--file'      => $file,
        ],
        keep_env => 1,
        stdout   => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                # $_[0]: chunk
                $combined_output .= $_[0];
                $stdout          .= $_[0];
            }
        ),
        stderr => Cpanel::CPAN::IO::Callback::Write->new(
            sub {
                # $_[0]: chunk
                $combined_output .= $_[0];
                $stderr          .= $_[0];
            }
        ),
    );

    if ( $run->CHILD_ERROR() ) {
        if ( $run->signal_code() || Cpanel::Tar::is_fatal_tar_stderr_output($stderr) ) {
            return ( 0, _locale()->maketext( "The [asis,tar] archive extraction failed because of the error “[_1]”: [_2]", $run->autopsy(), $combined_output ) );
        }

        $self->utils()->warn( _locale()->maketext( "The [asis,tar] archive extraction ended in error: [_1]", $run->autopsy() ) );

        if ( length $combined_output ) {
            $self->utils()->warn( _locale()->maketext( "The [asis,tar] archive extraction produced warnings: [_1]", $combined_output ) );
        }
    }

    # reset the permissions on "cwd" as tar could have changed them
    chmod( 0700, $dir ) or return ( 0, "Failed to chmod() 0700 $dir: $!" );

    #Since there is no reliable way that tar gives us to determine whether
    #any files were extracted, we have to read the directory.
    #
    #We could restrict this check to when tar exited in error,
    #but we might as well check for empty archives regardless.

    my ( $found_anything, $dir_err );

    try {
        $found_anything = Cpanel::FileUtils::Dir::directory_has_nodes($dir);
    }
    catch {
        $dir_err = $_;
    };

    if ($dir_err) {
        return ( 0, $dir_err->to_string() );
    }

    if ($found_anything) {
        return ( 1, _locale()->maketext("The [asis,tar] archive extraction was successful.") );
    }

    if ( $run->CHILD_ERROR() ) {
        return ( 0, _locale()->maketext('The system did not extract any files from the archive.') );
    }

    return ( 0, _locale()->maketext('The archive appears to be empty.') );
}

sub get_username_from_extracted_archive {
    my ($self) = @_;

    die Cpanel::Carp::safe_longmess("get_username_from_extracted_archive should never be called before safely_prepare_package_for_restore!") if !length $self->{'_username'};

    return $self->{'_username'};
}

sub get_hostname {
    my ($self) = @_;

    my $old_hostname;

    # NB: We started including the old hostname to account archives
    # in a maintenance release of v76.
    local $@;
    warn if !eval {
        my $extractdir = $self->trusted_archive_contents_dir();
        $old_hostname = Cpanel::LoadFile::load_if_exists("$extractdir/hostname");
        1;
    };

    return $old_hostname;
}

sub get_old_homedirs {
    my ($self) = @_;

    return ( 1, $self->{'_get_old_homedirs'} ) if $self->{'_get_old_homedirs'};

    my $extractdir = $self->trusted_archive_contents_dir();

    my @paths = map { "$extractdir/$_" } qw( meta/homedir_paths  homedir_paths );

    my $paths_file_path = Cpanel::ArrayFunc::first( sub { -e }, @paths );

    $self->{'_get_old_homedirs'} = [];
    return ( 1, [] ) if !$paths_file_path;

    my $paths_content_sr = Cpanel::LoadFile::loadfile_r($paths_file_path) or do {
        return ( 0, _locale()->maketext( 'The system failed to read the file “[_1]” because of an error: “[_2]”.', $paths_file_path, $! ) );
    };

    $self->{'_get_old_homedirs'} = [ split m{\n}, $$paths_content_sr ];

    return ( 1, $self->{'_get_old_homedirs'} );
}

sub archive_has_cpuser_data {
    my ($self) = @_;

    my $file;

    my $username   = $self->get_username_from_extracted_archive();
    my $extractdir = $self->trusted_archive_contents_dir();

    $file = "$extractdir/cp/$username";

    return ( -s $file ) && $file;
}

#NOTE: This does NOT validate!
sub get_raw_cpuser_data_from_archive {
    my ($self) = @_;

    my $file = $self->archive_has_cpuser_data();

    if ( !$file ) {
        return ( 0, _locale()->maketext('This archive does not contain [asis,cpuser] data.') );
    }

    my $cpuser_size = ( stat($file) )[7];

    if ( $cpuser_size > $MAX_CPUSER_FILE_SIZE ) {
        return ( 0, _locale()->maketext( 'This archive’s [asis,cpuser] data is unreasonably large ([format_bytes,_1]).', $cpuser_size ) );
    }

    my ( $cpuser_data, $err );
    try {
        Cpanel::Autodie::open( my $fh, '<', $file );

        # Avoid safefile since there is no need to lock
        # and we may be on NFS
        $cpuser_data = Cpanel::Config::LoadCpUserFile::parse_cpuser_file($fh);
    }
    catch {
        $err = $_;
    };

    return ( 0, Cpanel::Exception::get_string($err) ) if $err;

    return ( 1, $cpuser_data );
}

sub cleanup {
    my ($self) = @_;

    if ( $self->{'_temp_extract_dir'} && -e $self->{'_temp_extract_dir'} ) {

        # Ensure we never clean /XXXX
        # These are various safety checks to avoid blowing away
        # any directories that should never be cleaned up
        my $target_with_trailing_slash = $self->{'_temp_extract_dir'};
        $target_with_trailing_slash =~ s{/+$}{};
        if ( ( $target_with_trailing_slash =~ tr{/}{} ) <= 1 ) {
            die "clean: Cannot cleanup top level directory: “$self->{'_temp_extract_dir'} ”.";
        }

        my $run = Cpanel::SafeRun::Object->new(
            program => '/bin/rm',
            args    => [ '--recursive', '--force', '--', $self->{'_temp_extract_dir'} ],
        );

        warn $run->stderr() . $run->autopsy() if $run->CHILD_ERROR();
    }

    return;
}

1;
