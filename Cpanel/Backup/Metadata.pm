package Cpanel::Backup::Metadata;

# cpanel - Cpanel/Backup/Metadata.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Backup::MetadataDB ();

use Cpanel::Debug                        ();
use Cpanel::PIDFile                      ();
use Cpanel::JSON                         ();
use Cpanel::PwCache                      ();
use Cpanel::Backup::Config               ();
use Cpanel::Umask                        ();
use Cpanel::Fcntl::Constants             ();
use Cpanel::FileUtils::Write::JSON::Lazy ();

use Try::Tiny;

use constant S_IFMT  => $Cpanel::Fcntl::Constants::S_IFMT;
use constant S_IFREG => $Cpanel::Fcntl::Constants::S_IFREG;
use constant S_IFDIR => $Cpanel::Fcntl::Constants::S_IFDIR;
use constant S_IFLNK => $Cpanel::Fcntl::Constants::S_IFLNK;

=head1 NAME

Cpanel::Backup::Metadata

=head1 DESCRIPTION

Library for building and maintaining Metadata Databases used by the File restoration feature in cPanel & WHM.

=head1 SYNOPSIS

    #Assuming backups have already been run

    use Cpanel::Backup::Metadata;
    use Cpanel::Logger();
    use Cpanel::Config::LoadCpConf::loadcpconf();

    Cpanel::Backup::Metadata::metadata_disabled_check(); #calls exit() on failure

    my $cpconf;

    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
    my $today = sprintf "%04d-%02d-%02d", $year + 1900, $mon + 1, $mday;

    (%$cpconf) = Cpanel::Config::LoadCpConf::loadcpconf();
    my $backup_dir = "$cpconf->{BACKUPDIR}/$today"
    Cpanel::Backup::Metadata::create_meta_master($backup_dir); #create $BACKUPDIR/$DATE/accounts/.master.meta for use later

    my $logger = Cpanel::Logger->new( { 'timestamp_prefix' => 1 } );

    foreach my $user (qw{joe bob}) {
        my $master_meta = load_master_meta($backup_dir);

        my $backup_type = $master_meta->{$user}->{'backup_type'};
        $backup_type = $master_meta->{'users'}->{$user}->{'backup_type'} if !defined $backup_type;
        if ($backup_type == Cpanel::Backup::Metadata::BACKUP_TYPE_INCREMENTAL) {
            process_metadata_from_incremental($user, $today, $backup_dir, $logger);
        } else {
            my $tarball = "$backup_dir/accounts/$user.tar";
            $tarball .= ".gz" if $backup_type == Cpanel::Backup::Metadata::BACKUP_TYPE_COMPRESSED
            process_metadata_from_tar($user, $tarball, $today, $backup_dir, $logger);
        }

    }

    vacuum_metadata($logger) unless vacuum_is_running();

=cut

use constant {
    METADATA_ENTRY_TYPE_LINK => 2,
    METADATA_ENTRY_TYPE_DIR  => 1,
    METADATA_ENTRY_TYPE_FILE => 0,

    BACKUP_TYPE_UNCOMPRESSED => 0,
    BACKUP_TYPE_COMPRESSED   => 1,
    BACKUP_TYPE_INCREMENTAL  => 2,
    BACKUP_TYPE_OTHER        => 3,

    BACKUP_ALREADY_PROCESSED_ERROR => 'BACKUP_ALREADY_PROCESSED',
};

our $current_metaversion = Cpanel::Backup::MetadataDB::_SCHEMA_VERSION;
our $master_meta_name    = '.master.meta';
our $vacuum_pid_file     = '/var/cpanel/vacuum_metadata.pid';

our $pkgacct_version = 10;
our $archive_version = 4;
our $backup_master_dir;

our $ADD_OPERATION    = 0;
our $CHANGE_OPERATION = 1;
our $REMOVE_OPERATION = 2;

my %parsed_datetime_cache;

sub _get_uuid_text {
    require Cpanel::UUID if !$INC{'Cpanel/UUID.pm'};    # Saves an op
    return uc Cpanel::UUID::random_uuid();
}

=head1 SUBROUTINES

=head2 master_meta_file($backup_dir)

Return the expected location of the meta master file in the provided backup_dir.
backup_dir can contain the 'accounts' segment and this is tolerated appropriately.
Dies if the caller passes in a falsey path.

=cut

sub master_meta_file {
    if ( !$_[0] ) {

        # Cpanel::Exception brings in full locale system, don't load it unless absolutely needed
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'backup_dir' ] );
    }

    # Detect whether the caller already has 'accounts' as a path component
    my $path = ( index( $_[0], '/accounts' ) != -1 ) ? $_[0] : $_[0] . '/accounts/';
    $path = $path . '/' if substr( $path, -1, 1 ) ne '/';
    return $path . $master_meta_name;
}

=head2 create_meta_master

A meta master file is needed in the /accounts dir.  This is a json file
that contains the backup type and users, to be a definitive source for
this information.

It is intended to be run from /bin/backup after the accounts dir is
created.  Users are added later.

The way this is intended to be used from /bin/backup

create_meta_master

append_users_to_meta_master called for each user as they are added
to the backup.

complete_meta_master called after the backup is complete.

=over 3

=item C<< $backup_dir >>

The location of the backup: /backup/2017-10-10

=item C<< $backup_type >>

compressed, uncompressed or incremental

=back

=cut

sub create_meta_master {
    my ( $backup_dir, $backup_type ) = @_;

    my $meta_master_fname = master_meta_file($backup_dir);
    return 0 if -e $meta_master_fname;

    my $umask_obj = Cpanel::Umask->new(0177);
    my $ref       = {
        'metadata_version' => $current_metaversion,
        'backup'           => {
            'backup_type' => $backup_type,
            'backup_path' => $backup_dir,
            'backup_id'   => _get_uuid_text(),
        },
        'Status' => 'Successful',
    };

    if ( $backup_dir =~ m/\/(\d\d\d\d)-(\d\d)-(\d\d)/a ) {
        my $year = int($1);
        my $mon  = int($2);
        my $day  = int($3);

        my $date = {
            "Year"   => $year,
            "Month"  => $mon,
            "Day"    => $day,
            "Hour"   => 0,
            "Minute" => 0,
            "Second" => 0,
        };

        $ref->{'backup'}->{'Date'} = $date;
    }

    Cpanel::FileUtils::Write::JSON::Lazy::write_file_pretty( $meta_master_fname, $ref, 0600 );

    return 1;
}

=head2 load_master_meta(backup_dir)

Get a master meta hashref from the provided backup directory.

If there is no master_meta file in the backup_dir, you will get the following
in return.

{ 'backup_dir' => $backup_dir, 'backup_type' => 'ERROR', 'users' => [] }

Exceptions are thrown if there are problems reading the master_meta file.

=cut

sub load_master_meta {
    my ($backup_dir) = @_;
    my $meta_master_fname = master_meta_file($backup_dir);

    return { 'backup_dir' => $backup_dir, 'backup_type' => 'ERROR', 'users' => [] } if !-r $meta_master_fname;
    return Cpanel::JSON::LoadFile($meta_master_fname);
}

=head2 write_master_meta(master_meta, backup_dir)

Write the provided master meta hashref to accounts/.master.meta in the provided backup_dir.

=cut

sub write_master_meta {
    my ( $master_meta, $backup_dir ) = @_;

    my $meta_master_fname = $backup_dir . '/accounts/' . $master_meta_name;

    Cpanel::FileUtils::Write::JSON::Lazy::write_file_pretty( $meta_master_fname, $master_meta, 0600 );

    return;
}

=head2 _get_backup_master_dir()

Returns the backup directory and ensures whatever is configured exists, creating it if need be.

=cut

sub _get_backup_master_dir {
    if ( !defined $backup_master_dir ) {
        my $conf = Cpanel::Backup::Config::load();
        $backup_master_dir = $conf->{'BACKUPDIR'};
        $backup_master_dir //= '/backup';
        $backup_master_dir =~ s{/+$}{}g;
    }

    if ( !-d $backup_master_dir ) {
        require Cpanel::Mkdir;
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $backup_master_dir, 0711 );
    }

    return $backup_master_dir;
}

=head2 get_metadata_filename(user)

Get the appropriate metadata database file name for the provided user.

=cut

sub get_metadata_filename {
    my ($user) = @_;

    my ($metadata_dir);

    try {
        $metadata_dir = Cpanel::Backup::MetadataDB::base_path();
    }
    catch {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'Backup::MetadataConfigurationError', 'The system is unable to access metadata. Error: “[_1]”.', $_ );
    };

    if ( !-d $metadata_dir ) {
        require Cpanel::Mkdir;
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $metadata_dir, 0700 );
    }

    my $metadata_filename = $metadata_dir . '/' . $user . '.db';
    return $metadata_filename;
}

=head2 metadata_disabled_check
Checks to see if metadata and related features should be disabled
This check covers different scenarios.

=over 3

=item 1) If DISABLE_METADATA is enabled in the backup config

=item 2) If KEEPLOCAL is disabled in the backup config, as the backup data needed to restore from
   will never be available, rendering the entire feature useless until we get support for restoring
   from remote backups

=item 3) If the BACKUPDIR from the backup config is set with BACKUPMOUNT enabled, the backup data would only
   be available during a backup run. We could mount and unmount the directory every time a query is made,
   but the complexity is high when the setting could be changed instead.

=item 4) If BACKUPACCTS is disabled in the backup config, we won't be creating and data for accounts.

=item 5) if BACKUPENABLE is disabled in the backup config, we don't have any backups available at all.

=back

=over 3

B<Inputs>: $return_or_print

    <boolean>
        0 = return with status code and message
        1 = print message and exit with status code if disabled; return quietly if enabled

B<Returns>: $err_code, $err_msg

    $err_code = <integer>
        0 = Feature is enabled and available
        1 = Feature is disabled due to DISABLE_METADATA backup config setting being enabled
        2 = Feature is disabled due to KEEPLOCAL backup config setting being disabled
        3 = Feature is disabled due to BACKUPMOUNT backup config setting being enabled
        4 = Feature is disabled due to BACKUPACCTS backup config setting being disabled
        5 = Feature is disabled due to BACKUPENABLE backup config setting being disabled

    $err_msg = <scalar>
        Scalar string with error message if $return_or_print is set to 0

=back
=cut

# Changes to enable/disable criteria must happen here and at the tail end of Cpanel::Backup::Config::save()
sub metadata_disabled_check {
    my ($return_or_print) = @_;
    my $err_code = 0;
    my $err_msg;
    require Cpanel::Locale;
    my $locale = Cpanel::Locale->get_handle();

    if ( $< != 0 ) {
        return ( 99, $locale->maketext('You must run this code as the [asis,root] user.') );
    }

    # This is going to be HTML-escaped on the frontend.
    my $context = $locale->set_context_plain();

    # We can check /var/cpanel/config/backups/metadata_disabled to see if it's enabled or not, but in this case we want to report details
    my $config_hr = Cpanel::Backup::Config::get_normalized_config();

    if ( defined( $config_hr->{'disable_metadata'} ) && $config_hr->{'disable_metadata'} ) {
        $err_msg //= $locale->maketext('You cannot create or use metadata because the [asis, DISABLE_METADATA] setting in the backup configuration file is currently enabled.');
        $err_msg .= ' ' . $locale->maketext('Your system administrator must manually disable this setting on the command line with the WHM API 1 backup_config_set function to enable the [output,em,File and Directory Restoration] feature.');
        $err_code = 1;
    }
    elsif ( defined( $config_hr->{'keeplocal'} ) && !$config_hr->{'keeplocal'} ) {
        $err_msg //= $locale->maketext('You cannot create or use metadata because the setting [output,em,Retain backups in the default backup directory] is currently disabled.');
        $err_msg .= ' ' . $locale->maketext('Your system administrator must enable this setting in WHM’s [output,em,Backup Configuration] interface to enable the [output,em,File and Directory Restoration] feature.');
        $err_code = 2;
    }
    elsif ( defined( $config_hr->{'backupmount'} ) && $config_hr->{'backupmount'} ) {
        $err_msg //= $locale->maketext('You cannot create or use metadata because the setting [output,em,Mount Backup Drive as Needed] is currently enabled.');
        $err_msg .= ' ' . $locale->maketext('Your system administrator must disable this setting in WHM’s [output,em,Backup Configuration] interface to enable the [output,em,File and Directory Restoration] feature.');
        $err_code = 3;
    }
    elsif ( defined( $config_hr->{'backupaccts'} ) && !$config_hr->{'backupaccts'} ) {
        $err_msg //= $locale->maketext('You cannot create or use metadata because the setting [output,em,Backup Accounts] is currently disabled.');
        $err_msg .= ' ' . $locale->maketext('Your system administrator must enable this setting in WHM’s [output,em,Backup Configuration] interface to enable the [output,em,File and Directory Restoration] feature.');
        $err_code = 4;
    }
    elsif ( defined( $config_hr->{'backupenable'} ) && !$config_hr->{'backupenable'} ) {
        $err_msg //= $locale->maketext('You cannot create or use metadata because the setting [output,em,Backup Status] is currently disabled.');
        $err_msg .= ' ' . $locale->maketext('Your system administrator must enable this setting in WHM’s [output,em,Backup Configuration] interface to enable the [output,em,File and Directory Restoration] feature.');
        $err_code = 5;
    }

    $locale->set_context($context);

    if ($err_code) {
        if ( !$return_or_print ) {
            return ( $err_code, $err_msg );
        }
        else {
            print $err_msg . "\n";
            exit $err_code;    ## no critic qw(Cpanel::NoExitsFromSubroutines) - existing sub
        }
    }
    else {
        return ( 0, "Success" );
    }
}

=head2 metadata_disabled_check_scalar
Calls metadata_disabled_check and returns the scalar error/success code.
See metadata_disabled_check.

=over 3

B<Inputs>: $return_or_print

    <boolean>
        0 = return with status code and message
        1 = print message and exit with status code if disabled; return quietly if enabled

B<Returns>: $err_code

    $err_code = <integer>
        0 = Feature is enabled and available
        1 = Feature is disabled due to DISABLE_METADATA backup config setting being enabled
        2 = Feature is disabled due to KEEPLOCAL backup config setting being disabled
        3 = Feature is disabled due to BACKUPMOUNT backup config setting being enabled
        4 = Feature is disabled due to BACKUPACCTS backup config setting being disabled
        5 = Feature is disabled due to BACKUPENABLE backup config setting being disabled


=back
=cut

sub metadata_disabled_check_scalar {
    my ($err_code) = metadata_disabled_check(@_);
    return $err_code;
}

sub introspect_old_backup {
    my ($backup_dir) = @_;

    # first check for meta files, that will tell us the users names

    my $dir = $backup_dir . '/accounts';

    require Cpanel::FileUtils::Dir;
    my $files_ref = Cpanel::FileUtils::Dir::get_directory_nodes($dir);

    my $backup_type  = 'ERROR';
    my $output_users = {};
    my $auser;

    foreach my $file ( sort @{$files_ref} ) {

        my ( $user, $current_type );

        if ( -d "$dir/$file" ) {
            $user = $file;
            my $metadata = $dir . "/" . $user . '/backup_meta_data';
            if ( -e $metadata ) {
                $current_type = BACKUP_TYPE_INCREMENTAL;    # incremental
            }
        }
        if ( $file =~ m/^(.+)\.tar\.gz$/ ) {
            $user         = $1;
            $current_type = BACKUP_TYPE_COMPRESSED;         # compressed
        }
        elsif ( $file =~ m/^(.+)\.tar$/ ) {
            $user         = $1;
            $current_type = BACKUP_TYPE_UNCOMPRESSED;       # uncompressed
        }

        next unless defined $current_type;

        $auser //= $user;
        $backup_type = $current_type;

        my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 2, 3 ];

        $output_users->{$user} = {
            'user'            => $user,
            'backup_type'     => $backup_type,
            'uid'             => $uid,
            'gid'             => $gid,
            'pkgacct_version' => $pkgacct_version,
            'archive_version' => $archive_version,
        };

    }

    my $date;
    if ($auser) {
        require Cpanel::Backup::StreamFileList;
        my $backup_ref = Cpanel::Backup::StreamFileList::categorize_backup( _get_backup_master_dir(), $backup_dir, $auser );
        die "Invalid backup dir" if ( $backup_ref->{'backupID'} eq 'ERROR' );

        # get Date
        if ( $backup_ref->{'backupID'} =~ m/(\d{4})-(\d{2})-(\d{2})$/a ) {
            my $year  = $1;
            my $month = $2;
            my $day   = $3;

            $date = {
                "Year"   => int($year),
                "Month"  => int($month),
                "Day"    => int($day),
                "Hour"   => 0,
                "Minute" => 0,
                "Second" => 0,
            };
        }
        else {
            my $mtime = ( stat($backup_dir) )[9];
            my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime($mtime);
            $year += 1900;
            $mon++;

            $date = {
                "Year"   => $year,
                "Month"  => $mon,
                "Day"    => $mday,
                "Hour"   => 0,
                "Minute" => 0,
                "Second" => 0,
            };
        }
    }
    else {
        return {
            'metadata_version' => $current_metaversion,
            'users'            => $output_users,
            'backup'           => {
                'backup_type' => $backup_type,
                'backup_path' => $backup_dir,
                'backup_id'   => 'ERROR',
            }
        };
    }

    return {
        'metadata_version' => $current_metaversion,
        'users'            => $output_users,
        'backup'           => {
            'backup_type' => $backup_type,
            'backup_path' => $backup_dir,
            'backup_id'   => _get_uuid_text(),
            "Date"        => $date,
        },
        'Status' => 'Successful',
    };
}

sub _recover_from_inconsistent_backup_paths_table {
    my (%OPTS) = @_;
    my ( $dbh, $user, $backup_id, $backup_timestamp, $recorded_backup_path, $logger ) = @OPTS{qw( dbh user backup_id backup_timestamp backup_path logger )};
    $logger->info("It appears backup metadata creation failed for '$user' previously.  Attempting to Fix...");
    eval { $dbh->do("ROLLBACK TRANSACTION") };    #Just in case the last one was dangling
    $dbh->do("BEGIN EXCLUSIVE TRANSACTION;");

    # Impromptu reap; this should be OK given the caller is not going to short-circuit process_metadata_from* in the case of failures
    $dbh->do( "DELETE FROM backup_paths WHERE backup_id=? AND backup_path=?;", undef, $backup_id, $recorded_backup_path, 1 );
    $dbh->do( "DELETE FROM backups WHERE timestamp=?", undef, $backup_timestamp, 1 );

    # Only kill the file_changes for this backup_id if we don't have one from another backup that *may* have completed correctly
    $dbh->do("DELETE FROM file_changes WHERE backup_id NOT IN (SELECT distinct(backup_id) FROM backup_paths);");
    $dbh->do("DELETE FROM seen_files WHERE file_id NOT IN (SELECT DISTINCT(seen_files_id) FROM file_changes);");
    $dbh->do("COMMIT TRANSACTION;");

    return;
}

=head2 process_metadata_from_incremental(user, backup_date, backup_path, Cpanel::Logger)

Process the metadata for a user given a backup date and path.  Requires a Cpanel::Logger as its callers are all scripts.

=cut

sub process_metadata_from_incremental {
    my ( $user, $backup_date, $backup_path, $logger ) = @_;

    my $work_dir = $backup_path . '/' . $backup_date . '/accounts/' . $user;
    if ( !-d $work_dir ) {
        $logger->error("Can't use $work_dir as an incremental backup path : $!");
        return;
    }

    my $recorded_backup_path = $backup_path . '/' . $backup_date . '/accounts';

    _do_process_metadata(
        user      => $user,
        date      => $backup_date,
        path      => $recorded_backup_path,
        logger    => $logger,
        full_path => $recorded_backup_path,
        todo      => sub {
            my (%OPTS) = @_;

            my ( $dbh, $mass_inserter, $first_run_mass_inserter, $node_buffer_ar, $backup_id ) = @OPTS{qw( dbh mass_inserter first_run_mass_inserter node_buffer backup_id  )};

            _incremental_find_files(
                user                    => $user,
                work_dir                => $work_dir,
                backup_path             => $backup_path,
                node_buffer             => $node_buffer_ar,
                backup_id               => $backup_id,
                first_run_mass_inserter => $first_run_mass_inserter,
                dbh                     => $dbh,
                mass_inserter           => $mass_inserter,
            );

            return;
        },
    );

    return;
}

sub _incremental_find_files {
    my (%OPTS) = @_;

    my ( $dbh, $mass_inserter, $user, $first_run_mass_inserter, $work_dir, $backup_path, $node_buffer_ar, $backup_id ) = @OPTS{qw(dbh mass_inserter user first_run_mass_inserter work_dir backup_path node_buffer backup_id)};

    my $chunk_size = $mass_inserter->chunk_size();

    my $homedir                  = "$work_dir/homedir";
    my $relative_path_strip_size = length $homedir;
    my ( $mode, $size, $mtime, $relative_path, $file_type, $entry_type );
    require Cpanel::SafeFind;
    Cpanel::SafeFind::find(
        sub {
            ( $mode, $size, $mtime ) = ( lstat($_) )[ 2, 7, 9 ];
            $file_type = $mode & S_IFMT;
            if ( $file_type == S_IFREG ) {
                $entry_type = METADATA_ENTRY_TYPE_FILE;
            }
            elsif ( $file_type == S_IFDIR ) {
                return if $_ eq '.';
                $entry_type = METADATA_ENTRY_TYPE_DIR;

                # If the path is a directory, save it size as 0 bytes to match what we use for tar output, otherwise
                # it sees it as a change going between compressed and incremental backups
                $size = 0;

                # If the path is a directory, don't save the mtime. It was more noise than help.
                $mtime = 0;
            }
            elsif ( $file_type == S_IFLNK ) {
                $entry_type = METADATA_ENTRY_TYPE_LINK;

                # If the path is a link, save it size as 0 bytes to match what we use for tar output, otherwise
                # it sees it as a change going between compressed and incremental backups
                $size = 0;
            }
            else {
                $entry_type = METADATA_ENTRY_TYPE_FILE;

                # This is likely a socket file or named pipe
                $size = 0;
            }

            # Get full path from File::Find and transform to relative path for entries only in the homedir
            $relative_path = substr( $File::Find::name, $relative_path_strip_size );

            # Skip mail and .cpanel and prune so we do not descend
            if (   $relative_path eq '/mail'
                || index( $relative_path, '/mail/' ) == 0
                || $relative_path eq '/.cpanel'
                || index( $relative_path, '/.cpanel/' ) == 0 ) {
                $File::Find::prune = 1;
                return;
            }

            # Remove seconds from file's mtime to match what we get from current versions of tar output
            if ($mtime) {
                $mtime -= ( $mtime % 60 );
            }

            push @$node_buffer_ar, [ $relative_path, $size, $entry_type, $mtime, $backup_id ];

            # If we have iterated enough entries, flush the buffer to the databasee and start a new buffer
            if ( scalar @$node_buffer_ar >= $chunk_size ) {
                _flush_node_buffer( $dbh, $mass_inserter, $first_run_mass_inserter, $node_buffer_ar );
            }

        },
        $homedir,
    );

    return;
}

sub _flush_node_buffer {
    my ( $dbh, $mass_inserter, $first_run_mass_inserter, $node_buffer ) = @_;

    if ($first_run_mass_inserter) {

        #These are unique paths, you see...we only care if we've ever seen this in any backup, so it doesn't matter if we can't add it.
        $first_run_mass_inserter->insert_fields_sql_ar( [ map { $_->[0] } @$node_buffer ] );

        #Unfortunately, they need to be in-place before we update the file_changes.  Such is the cost of lower disk usage & faster queries.
    }

    $mass_inserter->insert_fields_sql_ar( [ map { @{$_} } @$node_buffer ] );

    return @$node_buffer = ();
}

=head2 process_metadata_from_tar(user, tarball, backup_date, backup_path, Cpanel::Logger)

Process the metadata for a user given a tarball, backup date and path.  Requires a Cpanel::Logger as its callers all are scripts.

=cut

sub process_metadata_from_tar {
    my ( $user, $tarfile, $backup_date, $backup_path, $logger ) = @_;

    require Cpanel::Backup::MetadataDB;
    require Cpanel::FastSpawn::InOut;
    require Cpanel::Tar;

    if ( !-d $backup_path ) {
        $logger->warn("There is no $backup_path directory.");
        return;
    }

    {
        local $ENV{'TZ'} = ':UTC';
        require POSIX;
        POSIX::tzset();    # Ensure the POSIX::mktime in _parse_tar_line is expecting to be handed UTC values

        _do_process_metadata(
            user      => $user,
            date      => $backup_date,
            path      => $backup_path,
            full_path => $tarfile,
            logger    => $logger,
            todo      => sub {
                my (%OPTS) = @_;

                my ( $dbh, $mass_inserter, $first_run_mass_inserter, $node_buffer_ar, $backup_id ) = @OPTS{qw( dbh mass_inserter first_run_mass_inserter node_buffer backup_id )};

                my ( $tar_homedir, $tar_homedir_match, $line_buffer_ar );

                my $tarcfg  = Cpanel::Tar::load_tarcfg();
                my @tarargs = ( '-t', '-v', '-f', $tarfile );
                if ( $tarcfg->{'dashdash_utc'} ) {
                    push @tarargs, '--utc';
                }
                else {
                    die "Tar must support --utc";
                }
                push @tarargs, '--numeric-owner';

                my $tarpid = Cpanel::FastSpawn::InOut::inout( my $wtrtar, my $rdrtar, $tarcfg->{'bin'}, @tarargs );
                close($wtrtar);
                my $chunk_size = $mass_inserter->chunk_size();
                my $tar_homedir_length;

                # not unpacking for speed
                while ( readline($rdrtar) ) {
                    if ( !defined $tar_homedir ) {
                        if (m/[ ]\Q$user\E\//) {
                            $tar_homedir = "$user/homedir";
                        }
                        elsif (m/[ ]cpmove-\Q$user\E\//) {
                            $tar_homedir = "cpmove-$user/homedir";
                        }
                        else {
                            my $error = "Unable to determine homedir path in tar file '$tarfile' from tar manifest line: $_";
                            $logger->error($error);
                            require Cpanel::Debug;
                            Cpanel::Debug::log_die($error);
                        }
                        $tar_homedir_length = length $tar_homedir;
                        $tar_homedir_match  = "$tar_homedir/";
                    }

                    $line_buffer_ar = _parse_tar_line( $_, $tar_homedir_match, $tar_homedir_length );
                    next if !$line_buffer_ar || !@$line_buffer_ar;
                    push( @$line_buffer_ar, $backup_id );

                    push @$node_buffer_ar, $line_buffer_ar;

                    if ( scalar @$node_buffer_ar >= $chunk_size ) {
                        _flush_node_buffer( $dbh, $mass_inserter, $first_run_mass_inserter, $node_buffer_ar );
                    }
                }
                close($rdrtar);

                waitpid( $tarpid, 0 );
            }
        );
    }

    # Above we changed our timezone to :UTC in order to ensure
    # _parse_tar_line would be processing the input as :UTC
    # now switch back to what it was before
    POSIX::tzset();

    return;
}

sub _do_process_metadata {
    my (%OPTS) = @_;

    my ( $user, $backup_date, $backup_path, $full_backup_path, $logger, $todo_cr ) = @OPTS{qw( user date path full_path logger todo )};

    try {
        my $dbh = Cpanel::Backup::MetadataDB->dbconnect( user => $user );
        my $backup_timestamp;

        {
            local $ENV{'TZ'} = ':UTC';
            require POSIX;
            POSIX::tzset();    # Set UTC -- see comments in process_metadata_from_tar
            $backup_timestamp = _parse_time( $backup_date . ' 00:00' );
        }
        POSIX::tzset();        # Set back to what is was before -- see comments in process_metadata_from_tar
        if ( my $backup_id = _backup_timestamp_exists( $dbh, $backup_timestamp ) ) {
            $logger->info("A backup with the timestamp '$backup_timestamp' was already was processed for the user '$user'.");

            my $failed      = 0;
            my $previous_id = _get_backup_id_from_path( $dbh, $backup_path );
            if ( !defined $previous_id ) {
                $logger->info("The backup with timestamp '$backup_timestamp' has a different path than the previous run '$backup_path'. Creating an alias.");

                # If this fails, it's because 1. the meta version is wrong, which should be guarded against, or 2. we had a backup metadata run fail midstream, and we're dirty

                try {
                    $dbh->do("BEGIN EXCLUSIVE TRANSACTION;");
                    $dbh->do( "INSERT INTO backup_paths (backup_id, backup_path) VALUES (?,?);", undef, $backup_id, $backup_path );
                    $dbh->do("COMMIT TRANSACTION;");
                }
                catch {
                    $failed = 1;
                    _recover_from_inconsistent_backup_paths_table(
                        dbh              => $dbh,
                        user             => $user,
                        backup_id        => $backup_id,
                        backup_timestamp => $backup_timestamp,
                        backup_path      => $backup_path,
                        logger           => $logger
                    );
                };
            }

            # We have to nuke the rest of the data 'just to be sure' in this situation
            if ( !$failed ) {

                # We know this backup has already been processed for this user, so skip
                die BACKUP_ALREADY_PROCESSED_ERROR();
            }
        }

        $dbh->do("BEGIN EXCLUSIVE TRANSACTION;");

        $dbh->do( "INSERT INTO backups (timestamp, does_exist) VALUES (?,?);", undef, $backup_timestamp, 1 );
        my $backup_id = $dbh->last_insert_id( "", "", "backups", "" );
        $dbh->do( "INSERT INTO backup_paths (backup_id, backup_path) VALUES (?,?);", undef, $backup_id, $backup_path );

        my @node_buffer;

        my $mass_inserter;
        my $first_run_mass_inserter;

        require Cpanel::SQLite::MassInsert;
        if ( _first_run( $dbh, $backup_id ) ) {
            $first_run_mass_inserter = Cpanel::SQLite::MassInsert->new(
                'query'      => q{INSERT OR IGNORE INTO seen_files (path) VALUES},
                'fields_sql' => q{(?)},
                'dbh'        => $dbh
            );
            $mass_inserter = Cpanel::SQLite::MassInsert->new(
                'query'      => q{INSERT INTO file_changes (seen_files_id, size, type, mtime, backup_id) VALUES},
                'fields_sql' => q{( (SELECT file_id FROM seen_files WHERE path=? ), ?, ?, ?, ? )},
                'dbh'        => $dbh
            );
        }
        else {
            $dbh->do("CREATE TEMPORARY TABLE infile (path TEXT, size INT, type INT, mtime INT, new INT DEFAULT 0, backup_id INT);");
            $dbh->do("CREATE INDEX IF NOT EXISTS infile_path_index ON infile (path);");
            $dbh->do("CREATE INDEX IF NOT EXISTS infile_path_size_mtime_type_index ON infile (path, size, mtime, type);");

            $mass_inserter = Cpanel::SQLite::MassInsert->new(
                'query'      => q{INSERT INTO infile (path, size, type, mtime, backup_id) VALUES},
                'fields_sql' => q{( ?, ?, ?, ?, ? )},
                'dbh'        => $dbh
            );
        }

        try {

            $todo_cr->(
                dbh                     => $dbh,
                mass_inserter           => $mass_inserter,
                node_buffer             => \@node_buffer,
                first_run_mass_inserter => $first_run_mass_inserter,
                backup_id               => $backup_id,
            );

            %parsed_datetime_cache = ();

            _flush_node_buffer( $dbh, $mass_inserter, $first_run_mass_inserter, \@node_buffer ) if (@node_buffer);

            # If we have other backups in the database we need to compare against, feed it through _generate_changeset()
            _generate_changeset( $dbh, $backup_id ) unless $first_run_mass_inserter;
            $dbh->do("COMMIT TRANSACTION;");
        }
        catch {
            $dbh->do("ROLLBACK TRANSACTION;");
            local $@ = $_;    # rethrow
            die;
        };

    }
    catch {
        my $error_check_name = BACKUP_ALREADY_PROCESSED_ERROR();
        if ( $_ !~ /\Q$error_check_name\E/ ) {
            require Cpanel::Exception;
            die Cpanel::Exception::create( 'Backup::CorruptedBackupData', 'The system was unable to interpret backup data. Error: “[_1]”.', [$_] );
        }
    };

    return;
}

=head2 append_users_to_meta_master

Appends users to the already created master.meta file.

It is intended to be run from /bin/backup as each user
is backed up.

=over 3

=item C<< $backup_dir >>

The location of the backup: /backup/2017-10-10

=item C<< @user_refs >>

Array of user_refs to append.

{
    'user' => 'cptest1',
    'backup_type' => 2
}

=back

=cut

sub append_users_to_meta_master {
    my ( $backup_dir, $users_ref ) = @_;

    my $backup_type;
    my $ref = load_master_meta($backup_dir);

    if ( !exists $ref->{'users'} ) {
        $ref->{'users'} = {};
    }

    # actively prevent duplicate user names
    my %filter;
    foreach my $user_ref ( @{$users_ref} ) {
        my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam_noshadow( $user_ref->{'user'} ) )[ 2, 3 ];
        $user_ref->{'uid'}             = $uid;
        $user_ref->{'gid'}             = $gid;
        $user_ref->{'pkgacct_version'} = $pkgacct_version;
        $user_ref->{'archive_version'} = $archive_version;
        $filter{ $user_ref->{'user'} } = $user_ref;
    }

    foreach my $filtered_user ( sort keys %filter ) {
        $ref->{'users'}->{$filtered_user} = $filter{$filtered_user};
    }

    write_master_meta( $ref, $backup_dir );

    return;
}

=head2 complete_meta_master(backup_dir)

chmod the meta master in the provided directory 0400

=cut

sub complete_meta_master {
    my ($backup_dir) = @_;

    my $meta_master_fname = master_meta_file($backup_dir);
    require Cpanel::Autodie;
    Cpanel::Autodie::chmod( 0400, $meta_master_fname );

    return;
}

=head2 create_meta_master_with_users_from_introspect(backup_dir,introspect_ref)

Creates a meta master in the provided backup dir based on the provided introspect_ref,
which should be the output of introspect_old_backup().

=cut

sub create_meta_master_with_users_from_introspect {
    my ( $backup_dir, $introspect_ref ) = @_;

    my $meta_master_fname = master_meta_file($backup_dir);
    return 0 if -e $meta_master_fname;
    my $umask_obj = Cpanel::Umask->new(0177);
    Cpanel::FileUtils::Write::JSON::Lazy::write_file_pretty( $meta_master_fname, $introspect_ref, 0600 );

    complete_meta_master($backup_dir);

    return;
}

=head2 create_metadata_for_backup_user(backup_dir,user,logger)

Creates entries in the metadata DB for the provided user and the backup in the provided directory.
Generally you would be looping over users and backup dirs when calling this.

=cut

sub create_metadata_for_backup_user {
    my ( $backup_dir, $user, $logger ) = @_;

    return if metadata_disabled_check_scalar();

    my $master_meta = load_master_meta($backup_dir);
    return if !exists $master_meta->{'users'}->{$user};    # user does not exist in this backup

    my $backup_type = $master_meta->{$user}->{'backup_type'};
    $backup_type = $master_meta->{'users'}->{$user}->{'backup_type'} if !defined $backup_type;

    my $base_dir     = "$user/homedir";
    my $base_dir_len = length($base_dir);

    try {
        if (   $backup_type == BACKUP_TYPE_UNCOMPRESSED
            || $backup_type == BACKUP_TYPE_COMPRESSED ) {
            my $tarball = $backup_dir . "/accounts/$user.tar";
            $tarball .= ".gz" if ( $backup_type == BACKUP_TYPE_COMPRESSED );

            my $backup_date  = substr( $backup_dir, rindex( $backup_dir, '/' ) + 1 );
            my $accounts_dir = $backup_dir . "/accounts";

            process_metadata_from_tar( $user, $tarball, $backup_date, $accounts_dir, $logger );
        }
        elsif ( $backup_type == BACKUP_TYPE_INCREMENTAL ) {
            my $ridx = rindex( $backup_dir, '/' );

            my $backup_date = substr( $backup_dir, $ridx + 1 );
            my $backup_path = substr( $backup_dir, 0, $ridx );

            process_metadata_from_incremental( $user, $backup_date, $backup_path, $logger );
        }
    }
    catch {
        $logger->warn("Caught Error $_");
    };

    return;
}

=head2 create_metadata_for_backup(backup_dir,logger)

Sugar around create_metadata_for_backup_user.  Loops over all users for a given backup directory.

=cut

sub create_metadata_for_backup {
    my ( $backup_dir, $logger ) = @_;

    return if metadata_disabled_check_scalar();

    my $master_meta = load_master_meta($backup_dir);

    foreach my $user ( keys %{ $master_meta->{'users'} } ) {
        create_metadata_for_backup_user( $backup_dir, $user, $logger );
    }

    return;
}

=head2 prune_backup

Remove a backup and all it's meta data from the db.

=over 3

=item C<< $backup_dir >>

The location of the backup: /backup/2017-10-10

=back

=cut

sub prune_backup {
    my ($backup_dir) = @_;

    return if metadata_disabled_check_scalar();

    if ( length $backup_dir < 9 || substr( $backup_dir, -9 ) ne '/accounts' ) {
        $backup_dir = $backup_dir . '/accounts';
    }

    my @users = get_all_users();
    foreach my $user (@users) {
        try {
            _prune_backup_dir_for_user( $user, $backup_dir );
        }
        catch {
            require Cpanel::Debug;
            Cpanel::Debug::log_warn("There was an error pruning the backup dir '$backup_dir' for user '$user': $_");
        };
    }

    return;
}

=head2 is_vacuum_running

Find out if the metadata is being vacuumed

=over 3

B<Inputs>: None.

B<Returns>: Returns true if vacuum is running; false if not.

=back

=cut

sub is_vacuum_running {

    my $result = 0;

    try {
        my $pid = Cpanel::PIDFile->get_pid($vacuum_pid_file);

        if ($pid) {

            # Process is running
            if ( kill( 0, $pid ) > 0 ) {

                require Cpanel::PsParser;
                my $pid_info = Cpanel::PsParser::get_pid_info($pid);

                if ($pid_info) {

                    if ( ( $pid_info->{'command'} =~ /vacuum_metadata/ ) && ( $pid_info->{'state'} ne 'Z' ) ) {
                        $result = 1;
                    }
                }
            }

            # If the pidfile somehow exists & vacuum isn't running
            # Then it is invalid and will block vacuum from ever running
            # in the future.  It needs to be removed
            if ( !$result ) {
                unlink $vacuum_pid_file;
            }
        }
    };

    return $result;
}

=head2 set_backup_status

Set the status of the backup in the master meta file.

=over 3

=item C<< $backup_dir >>

The location of the backup: /backup/2017-10-10.

=item C<< $status >>

The status 1 = Successful | 0 = Failed.

=back

=cut

sub set_backup_status {
    my ( $backup_dir, $status ) = @_;

    return if metadata_disabled_check_scalar();

    my $master_meta = load_master_meta($backup_dir);
    $master_meta->{'Status'} = ( $status == 1 ) ? "Successful" : "Failed";
    write_master_meta( $master_meta, $backup_dir );

    return;
}

=head2 get_backup_type_text( INT backup_type)

Returns the text representation of the database flag for the given backup type.
See the BACKUP_TYPE_* constants for the valid database flag values.

Returns undef in the event you have an invalid backup type.

=cut

sub get_backup_type_text {
    my ($backup_type) = @_;

    my $backup_type_text;

    $backup_type_text = "uncompressed" if ( $backup_type == BACKUP_TYPE_UNCOMPRESSED );
    $backup_type_text = "compressed"   if ( $backup_type == BACKUP_TYPE_COMPRESSED );
    $backup_type_text = "incremental"  if ( $backup_type == BACKUP_TYPE_INCREMENTAL );
    $backup_type_text = "other"        if ( $backup_type == BACKUP_TYPE_OTHER );

    return $backup_type_text;
}

=head2 get_file_type_text( INT file_type)

Returns the text representation of the database flag for the given file type.
See the METADATA_ENTRY_TYPE_* constants for the valid database flag values.

Returns undef in the event you have an invalid file type.

=cut

sub get_file_type_text {
    my ($file_type) = @_;

    my $file_type_text;

    $file_type_text = "SYMLINK" if ( $file_type == METADATA_ENTRY_TYPE_LINK );
    $file_type_text = "DIR"     if ( $file_type == METADATA_ENTRY_TYPE_DIR );
    $file_type_text = "FILE"    if ( $file_type == METADATA_ENTRY_TYPE_FILE );

    return $file_type_text;
}

=head2 translate_backup_type

Convert from named backup types such as compressed to the numeric equivalent.

=over 3

=item C<< $backup_type >>

The backup_type such as "compressed".

=back

B<Returns>: Returns numeric equivalent 0-2 or if there is an error 3.

=cut

sub translate_backup_type {
    my ($backup_type) = @_;

    if ( $backup_type eq 'uncompressed' ) {
        $backup_type = 0;
    }
    elsif ( $backup_type eq 'compressed' ) {
        $backup_type = 1;
    }
    elsif ( $backup_type eq 'incremental' ) {
        $backup_type = 2;
    }
    else {
        $backup_type = 3;
    }

    return $backup_type;
}

=head2 translate_file_type(INT file_type)

like get_file_type_text, but returns values in lowercase and 'unknown' in the event of failure.

=cut

sub translate_file_type {
    my ($file_type) = @_;

    if ( $file_type == METADATA_ENTRY_TYPE_FILE ) {
        $file_type = 'file';
    }
    elsif ( $file_type == METADATA_ENTRY_TYPE_DIR ) {
        $file_type = 'dir';
    }
    elsif ( $file_type == METADATA_ENTRY_TYPE_LINK ) {
        $file_type = 'symlink';
    }
    else {
        $file_type = 'unknown';
    }

    return $file_type;
}

=head2 get_database_metaversion

Get the version of the metadata schema

=over 3

B<Inputs>: None.

B<Returns>: Returns database metaversion, or false in the event a user DB does not exist.

=back

=cut

sub get_database_metaversion {
    my ($user) = @_;

    return if !$user;
    return if metadata_disabled_check_scalar();

    my $user_db_path = get_metadata_filename($user);

    if ( -f $user_db_path ) {
        my $umask_obj = Cpanel::Umask->new(0177);
        require Cpanel::DBI::SQLite;
        my $dbh     = Cpanel::DBI::SQLite->connect( { 'database' => $user_db_path, RaiseError => 1 } );
        my $results = $dbh->selectall_arrayref( qq{SELECT key, value FROM metadata;}, { Slice => {} } );
        my ($v)     = grep { $_->{key} eq 'schema_version' } @$results;
        return $v->{value};
    }
    return '';
}

# this allows you to query a single username's database
sub is_user_database_valid {
    my ($user) = @_;

    my $is_valid = 1;

    try {
        my $version = get_database_metaversion($user);
        $is_valid = 0 if ( $version ne Cpanel::Backup::MetadataDB::_SCHEMA_VERSION );
    }
    catch {
        $is_valid = 0;
    };

    return $is_valid;
}

=head2 is_database_valid

Tests if the database(s) passed are valid by querying the metaversion.
The database is invalid if query throws an exception or
the metaversion is wrong.

=over 3

B<Inputs>: ARRAYREF of user DBs to check.  If omitted, will check all users with backups configured.

B<Returns>: Returns true if valid; false if not, and a HASHREF of the user DBs that were bad if any had problems.

=back

=cut

sub is_database_valid {
    my ($users_ar) = @_;

    return ( 1, undef ) if metadata_disabled_check_scalar();    # Don't need to trigger rebuilds if metadata isn't enabled

    my %bad_user_dbs;

    if ( ref $users_ar ne 'ARRAY' || !@$users_ar ) {
        @$users_ar = get_all_users();
    }

    foreach my $user ( @{$users_ar} ) {
        if ( !is_user_database_valid($user) ) {
            $bad_user_dbs{$user} = 1;
        }
    }

    my @keys = keys %bad_user_dbs;
    if (@keys) {
        return ( 0, \%bad_user_dbs );
    }

    return ( 1, undef );
}

=head2 get_all_users

Returns ARRAY of all user names with backup metadata that exists.

=cut

sub get_all_users {
    my $backup_base_path = Cpanel::Backup::MetadataDB::base_path();

    my @users;
    require Cpanel::Dir::Loader;
    foreach my $file ( Cpanel::Dir::Loader::load_dir_as_array($backup_base_path) ) {
        if ( $file =~ m/^([^\.]+)\.db$/ ) {
            my $user = $1;
            push( @users, $user );
        }
    }

    return @users;
}

=head2 vacuum_metadata

Remove unused space and defragment the database.

=over 3

=item C<< $logger >>

For logging of any vacuum related issues

=back

=cut

sub vacuum_metadata {
    my ($logger) = @_;

    return if metadata_disabled_check_scalar();

    # We don't want to vacuum the metadata if backups are running
    require Cpanel::Backup::Sync;
    if ( Cpanel::Backup::Sync::are_backups_running() ) {

        $logger->warn("Unable to vacuum the backup metadata when backups are running");
        return;
    }

    # We can't run vacuum if we are vacuuming
    # Plus, is_vacuum_running will remove an invalid pidfile
    # which would block Cpanel::PIDFile->do() from ever being able to run
    if ( is_vacuum_running() ) {

        $logger->warn("A vacuum operation is already being performed on the metadata");
        return;
    }

    # Surround this operation with a pid file so we can test if it is running
    Cpanel::PIDFile->do(
        $vacuum_pid_file,
        sub {
            $logger->info("Vacuum of metadata has begun");

            try {
                _perform_vacuum();
            }
            catch {
                $logger->warn("Error vacuuming metadata: $_");
            };

            $logger->info("Vacuum of metadata is complete");
        }
    );

    return;
}

=head2 remove_metadata_for_missing_backups

This will remove metadata for backups that no longer exist. Does nothing if backup metadata is disabled.
Returns undef (on success) or throws an exception (in case of error).

=cut

our $REMOVE_SLEEPTIME  = 5;
our $REMOVE_SLEEPCOUNT = 4;

sub remove_metadata_for_missing_backups {

    # Do nothing if metadata is disabled
    return if Cpanel::Backup::Metadata::metadata_disabled_check_scalar();

    my $conf_ref = Cpanel::Backup::Config::load();

    my %backups_exist;
    my @users = Cpanel::Backup::Metadata::get_all_users();
    foreach my $user (@users) {
        my $array_ref;
        my $loop_not_done = $REMOVE_SLEEPCOUNT;

        # HB-3747 - deal with SQLITE errors due to locked and other issues
        while ( $loop_not_done > 0 ) {
            try {
                my $dbh = Cpanel::Backup::MetadataDB->dbconnect( user => $user );
                $array_ref     = $dbh->selectall_arrayref("SELECT backup_path FROM backup_paths;");
                $loop_not_done = 0;

                # this is here for QA testing to verify success after a failure HB-3747
                Cpanel::Debug::log_info("Successfully gathered backup information for pruning older backups for $user");
            }
            catch {
                my $error_msg = $_;
                Cpanel::Debug::log_warn("Error retrieving backup information for $user. This can cause issues pruning backups. $error_msg");
                if ( $error_msg->failure_is('SQLITE_BUSY') ) {
                    sleep($REMOVE_SLEEPTIME) if --$loop_not_done;
                }
                else {

                    # The error message is NOT busy so retrying will not help,
                    # we will move on and depend on the auto heal
                    $loop_not_done = 0;
                }
            };
        }

        foreach my $dirs_ref ( @{$array_ref} ) {
            my $dir = $dirs_ref->[0];
            next if ( exists $backups_exist{$dir} );
            $backups_exist{$dir} = 1;
            $backups_exist{$dir} = 0 if !-d $dir;
        }
    }

    foreach my $dir ( keys %backups_exist ) {
        if ( $backups_exist{$dir} == 0 ) {
            prune_backup($dir);
        }
    }

    return;
}

sub _perform_vacuum {
    my @all_users = get_all_users();

    foreach my $user (@all_users) {
        my $dbh = Cpanel::Backup::MetadataDB->dbconnect( user => $user );
        $dbh->do("VACUUM;");
    }

    return;
}

sub _generate_changeset {
    my ( $dbh, $backup_id ) = @_;

    # Update the seen_files
    my $statement = $dbh->prepare("INSERT INTO seen_files (path) SELECT path FROM infile WHERE path NOT IN (SELECT path FROM seen_files)");
    $statement->execute();

    my $quoted_backup_id = $dbh->quote($backup_id);

    my $temp_table = <<END;
CREATE TEMPORARY TABLE previous_changeset
    (
        path TEXT,
        seen_files_id,
        size INT,
        mtime INT,
        type INT,
        backup_id INT
    );
END

    $dbh->do($temp_table);
    $dbh->do("CREATE INDEX IF NOT EXISTS previous_changeset_path_index ON previous_changeset (path);");
    $dbh->do("CREATE INDEX IF NOT EXISTS previous_changeset_path_backup_id_index ON previous_changeset (path, backup_id);");
    $dbh->do("CREATE INDEX IF NOT EXISTS previous_changeset_size_mtime_type_index ON previous_changeset (path, size, mtime, type);");
    $dbh->do("CREATE INDEX IF NOT EXISTS previous_changeset_sfid_index ON previous_changeset (seen_files_id);");

    my $populate_temp = <<END;
INSERT INTO previous_changeset
    (
        path,
        seen_files_id,
        size,
        mtime,
        type,
        backup_id
    )
    SELECT
        (SELECT path FROM seen_files WHERE f.seen_files_id=file_id) AS path,
        f.seen_files_id,
        f.size,
        f.mtime,
        f.type,
        MAX(f.backup_id) as backup_id
    FROM file_changes AS f
    GROUP BY path
    HAVING operation != $REMOVE_OPERATION;
END

    $dbh->do($populate_temp);

    my $add_files_insert = qq{
        INSERT INTO file_changes (backup_id,size,mtime,type, seen_files_id)
        SELECT
            backup_id,
            size,
            mtime,
            type,
            (SELECT file_id FROM seen_files WHERE added.path=seen_files.path) AS seen_files_id
        FROM
            (
                SELECT path FROM infile
                EXCEPT
                SELECT path FROM previous_changeset
            )
        AS added
        JOIN infile ON infile.path = added.path;
    };

    $dbh->do($add_files_insert);

    my $remove_files_insert = <<"END";
INSERT INTO file_changes
    (
        seen_files_id,
        backup_id,
        size,
        mtime,
        type,
        operation
    )
    SELECT
        (SELECT file_id FROM seen_files WHERE removed.path=seen_files.path) AS seen_files_id,
        $quoted_backup_id AS backup_id,
        -1,
        -1,
        -1,
        $REMOVE_OPERATION as operation
    FROM
        (
            SELECT path FROM previous_changeset
            EXCEPT
            SELECT path FROM infile
        )
    AS removed;
END

    $dbh->do($remove_files_insert);

    my $remove_modified = <<END;
DELETE FROM infile WHERE path IN ( SELECT s.path FROM file_changes AS f JOIN seen_files AS s ON s.file_id=f.seen_files_id WHERE f.backup_id = $quoted_backup_id );
END

    $dbh->do($remove_modified);

    my $changed_files_insert = <<"END";
INSERT INTO file_changes
    (
        seen_files_id,
        size,
        mtime,
        type,
        backup_id,
        operation
    )
    SELECT
        (SELECT file_id FROM seen_files WHERE changed.path=seen_files.path) AS seen_files_id,
        changed.size,
        changed.mtime,
        changed.type,
        $quoted_backup_id AS backup_id,
        $CHANGE_OPERATION as operation
    FROM
        (
            SELECT path, size, mtime, type FROM infile
            EXCEPT
            SELECT path, size, mtime, type FROM previous_changeset
        )
    AS changed;
END

    $dbh->do($changed_files_insert);

    return;
}

sub _get_backup_timestamp_from_id {
    my ( $dbh, $backup_id ) = @_;

    my $quoted_backup_id = $dbh->quote($backup_id);
    my $value            = $dbh->selectall_arrayref("SELECT timestamp FROM backups WHERE backup_id = $quoted_backup_id");
    return $value->[0][0];
}

sub _backup_timestamp_exists {
    my ( $dbh, $backup_timestamp ) = @_;

    my $quoted_backup_timestamp = $dbh->quote($backup_timestamp);
    my $value                   = $dbh->selectall_arrayref("SELECT backup_id FROM backups WHERE timestamp = $quoted_backup_timestamp");
    return $value->[0][0];
}

sub _get_backup_id_from_path {
    my ( $dbh, $backup_path ) = @_;

    my $quoted_backup_path = $dbh->quote($backup_path);
    my $value              = $dbh->selectall_arrayref("SELECT backup_id FROM backup_paths WHERE backup_path = $quoted_backup_path");
    return $value->[0][0];
}

sub _first_run {
    my ( $dbh, $backup_id ) = @_;

    my $quoted_backup_id = $dbh->quote($backup_id);
    my $values           = $dbh->selectall_arrayref("SELECT COUNT(*) FROM backups WHERE backup_id != $quoted_backup_id");

    return $values->[0][0] ? 0 : 1;
}

# $_[0] = $line
# $_[1] = $tarhomedir_match "$tarhomedir/"
# $_[2] = $tarhomedir_length
my ( $itype, $entry_type, $size, $datetime, $path );

sub _parse_tar_line {    ## no critic qw(Subroutines::RequireArgUnpacking) - not unpacking for speed

    if ( $_[0] =~ m{^([^l]).........\s+\d+\/\d+\s+(\d+)\s+(\d{4}-\d{2}-\d{2}+\s+\d{2}\:\d{2})\s+(.+)\n$}a ) {    # dir or file
        ( $itype, $size, $datetime, $path ) = ( $1, $2, $3, $4 );
        $entry_type = $itype eq 'd' ? METADATA_ENTRY_TYPE_DIR : METADATA_ENTRY_TYPE_FILE;
    }
    elsif ( $_[0] =~ m{^l.........\s+\d+\/\d+\s+(\d+)\s+(\d{4}-\d{2}\-\d{2}\s+\d{2}\:\d{2})\s+(.+)\s+->\s+.+\n$}a ) {    #symlink
        ( $size, $datetime, $path ) = ( $1, $2, $3 );
        $entry_type = METADATA_ENTRY_TYPE_LINK;
    }
    else {
        warn "Found unparsable tar line: " . $_[0];
        return;
    }

    # Return if the path does not start with homedir
    return if index( $path, $_[1] ) != 0;

    # Remove the $user/homedir prefix from all the files. Saves space and matching time
    substr( $path, 0, $_[2], '' );

    # We only want files in the user's homedir.. other files are irrelevant
    if (
        $path eq '/'
        ||

        # Skip mail
        $path eq '/mail' || index( $path, '/mail/' ) == 0 ||

        # Skip mail
        $path eq '/.cpanel' || index( $path, '/.cpanel/' ) == 0
    ) {
        return;
    }

    # lop trailing /
    chop $path if substr( $path, -1 ) eq '/';

    # Expensive, but pretty mandatory
    if ( index( $path, '\\' ) > -1 ) {
        require Cpanel::StringFunc::Coreutils if !$INC{'Cpanel/StringFunc/Coreutils.pm'};
        Cpanel::StringFunc::Coreutils::dequote($path);
    }

    if ( $entry_type == METADATA_ENTRY_TYPE_DIR ) {

        # Don't save mtime for directories. It was causing more noise than it helped.
        return [ $path, $size, $entry_type, 0 ];
    }

    return [ $path, $size, $entry_type, $parsed_datetime_cache{$datetime} ||= _parse_time($datetime) ];
}

# NOTE make sure you require POSIX module before running this sub, current callers all do this
sub _parse_time {    ## no critic qw(Subroutines::RequireArgUnpacking) - not unpacking for speed

    # $_[0] = $datetime
    return $parsed_datetime_cache{ $_[0] } if $parsed_datetime_cache{ $_[0] };

    my $mtime;
    if ( $_[0] =~ m/([0-9]{4})-([0-9]{2})-([0-9]{2}) ([0-9]{2}):([0-9]{2})/ ) {
        die if $ENV{'TZ'} ne ':UTC';

        # tzset must be called before this function
        # to ensure mktime sees the input as UTC
        $mtime = POSIX::mktime(
            0,           # sec
            $5,          # min
            $4,          # hour
            $3,          # mday
            $2 - 1,      # mon
            $1 - 1900    # year
        );
    }

    if ( !defined $mtime ) {
        require Cpanel::Debug;
        Cpanel::Debug::log_warn("Unable to parse time from tar file: $_[0]");
        return gmtime();
    }

    return ( $parsed_datetime_cache{ $_[0] } = $mtime );
}

sub _prune_backup_dir_for_user {
    my ( $user, $backup_dir ) = @_;

    my $dbh = Cpanel::Backup::MetadataDB->dbconnect( user => $user );

    # Check to see if this is an aliased backup_id, in which case we just
    # remove it from backup_paths

    my $backup_set      = $dbh->selectall_arrayref( qq{SELECT backup_id FROM backup_paths WHERE backup_path = ?;}, undef, $backup_dir );
    my $alias_backup_id = $backup_set->[0][0];
    $backup_set = $dbh->selectall_arrayref( qq{SELECT COUNT(backup_id) FROM backup_paths WHERE backup_id = ?;}, undef, $alias_backup_id );
    my $alias_count = $backup_set->[0][0];

    if ( $alias_count > 1 ) {
        $dbh->do( "DELETE FROM backup_paths WHERE backup_path = ?;", undef, $backup_dir );
        return;
    }
    elsif ( !$alias_count ) {
        return;
    }

    my $result_set = $dbh->selectall_arrayref( qq{SELECT backup_id FROM backups ORDER BY backup_id ASC;}, { Slice => {} } );

    next if !$result_set;

    my ( $backup_id, $previous_id, $next_id );

    for my $result (@$result_set) {
        if ( !length($backup_id) && $result->{'backup_id'} == $alias_backup_id ) {
            $backup_id = $alias_backup_id;
            next;
        }
        elsif ( !length($backup_id) ) {
            $previous_id = $result->{'backup_id'};
            next;
        }
        elsif ( length $backup_id && !length $next_id ) {
            $next_id = $result->{backup_id};
            last;
        }
    }

    my $quoted_backup_id   = $dbh->quote($backup_id);
    my $quoted_previous_id = $dbh->quote($previous_id);
    my $quoted_next_id     = $dbh->quote($next_id);

    # backup is in the middle
    if ( length $previous_id && length $next_id ) {

        # Pruning when the backup is in between two other backups. This can happen if an
        # admin deletes one of the backup directories. (-- means maybe warn/log/die in this case)
        #   change OP for path
        #       if next backup ID has no entry for path
        #           true: update current record to have the next backup ID
        #           false:
        #               if entry in next backup is:
        #                   remove entry - delete current entry
        #                   change entry - delete current entry
        #                 --  add entry    - SNH remove current entry
        #
        #   remove OP for path
        #       if next backup ID has no entry for path
        #           true: update current record to have next backup ID
        #           false:
        #               if entry in next backup is:
        #                 --  remove entry - SNH delete current entry
        #                 --  change entry - SNH delete current entry
        #                   add entry    - delete current entry and update next entry to change
        #
        #   add OP for path
        #       if following backup ID has no entry for path
        #           true: update current record to have next backup ID
        #           false:
        #               if entry in following backup is:
        #                   remove entry - delete current and next entry
        #                   change entry - delete current and update next to operation = ADDED
        #                 --  add entry    - SNH delete current entry
        #

        # Move all current entries to the next backup_id if there is no entry in that backup for the path
        my $handle_simple_move = <<END;
UPDATE file_changes
SET
    backup_id = $quoted_next_id
WHERE
    backup_id = $quoted_backup_id AND
    NOT EXISTS (SELECT seen_files_id FROM file_changes as f WHERE backup_id = $quoted_next_id AND file_changes.seen_files_id = f.seen_files_id)
END

        $dbh->do($handle_simple_move);

        # For every REMOVE entry we have in current backup, check to see if there is an ADD entry
        # in the next backup and change it to a CHANGE entry instead.
        my $handle_add_to_changed_for_removed_sql = <<END;
UPDATE file_changes
SET
    operation = $CHANGE_OPERATION
WHERE
    backup_id = $quoted_next_id AND
    operation = $ADD_OPERATION AND
    seen_files_id IN (SELECT seen_files_id FROM file_changes WHERE backup_id = $quoted_backup_id AND operation = $REMOVE_OPERATION)
END

        $dbh->do($handle_add_to_changed_for_removed_sql);

        # For every ADD entry we have in the current backup, check to see if there is a CHANGE entry
        # in the next backup and change it to an ADD entry instead.
        my $handle_change_to_add_for_add_sql = <<END;
UPDATE file_changes
SET
    operation = $ADD_OPERATION
WHERE
    backup_id = $quoted_next_id AND
    operation = $CHANGE_OPERATION AND
    seen_files_id IN (SELECT seen_files_id FROM file_changes WHERE backup_id = $quoted_backup_id AND operation = $ADD_OPERATION)
END

        $dbh->do($handle_change_to_add_for_add_sql);

        # For every ADD entry we have in the current backup, check to see if there is a REMOVE entry
        # in the next backup and remove it.
        my $handle_next_remove_if_add_removed = <<END;
DELETE from file_changes
WHERE
    backup_id = $quoted_next_id AND
    operation = $REMOVE_OPERATION AND
    seen_files_id IN (SELECT seen_files_id FROM file_changes WHERE backup_id = $quoted_backup_id AND operation = $ADD_OPERATION)
END

        $dbh->do($handle_next_remove_if_add_removed);

        # Just need to remove the remainder.. that happens below.
    }

    # backup is the first backup
    elsif ( !length $previous_id ) {

        # PRUNING BACKUP IS OLDEST (NORMAL PRUNING CASE?) (-- means maybe warn/log/die in this case)
        #  -- change OP for path (THIS SHOULDNT HAPPEN!!! (entry should have been changed to "ADDED") but just in case)
        #       if next backup ID has no entry for path
        #           true: update current entry to have next backup ID and operation = ADDED
        #           false:
        #               if entry in next backup is:
        #                   remove entry - delete current entry and next entry
        #                   change entry - delete current entry and make next entry operation = ADDED
        #                 --  add entry    - SNH delete current entry
        #
        #  -- remove OP for path (THIS SHOULDNT HAPPEN!!! ENTRY SHOULDNT EXIST but just in case)
        #       if next backup ID has no entry for path
        #           true: remove current entry
        #           false:
        #               if entry in next backup is:
        #                 --  remove entry - SNH delete current entry
        #                 --  change entry - SNH delete current entry and update next entry to operation = ADDED
        #                   add entry    - delete current entry
        #
        #   add OP for path
        #       if next backup ID has no entry for path
        #           true: update current entry to have next backup ID
        #           false:
        #               if entry in next backup is:
        #                   remove entry - delete current and next backup ID entry
        #                   change entry - delete current entry and update next entry to operation = ADDED
        #              --     add entry    - SNH delete current entry

        if ( length $next_id ) {

            # We've verified all operations at this backup are add operations, so
            # Move the current add operations to the next backup, if the
            # next backup doesn't have an entry for this path
            my $update_sql = <<END;
UPDATE file_changes
SET
    operation = $ADD_OPERATION,
    backup_id = $quoted_next_id
WHERE
    backup_id = $quoted_backup_id AND
    NOT EXISTS (SELECT seen_files_id FROM file_changes as f WHERE backup_id = $quoted_next_id AND file_changes.seen_files_id = f.seen_files_id);
END

            $dbh->do($update_sql);

            # If the file was removed in the next backup, remove that entry
            my $delete_next_remove_sql = <<END;
DELETE FROM file_changes
WHERE
    backup_id = $quoted_next_id AND
    operation = $REMOVE_OPERATION AND
    seen_files_id IN (SELECT seen_files_id FROM file_changes WHERE backup_id = $quoted_backup_id);
END

            $dbh->do($delete_next_remove_sql);

            # Now that we've removed the next remove entry it's safe to
            # change all entries for the current path in the next backup
            # to be adds. That backup is now the first, so it should be only add entries.
            my $update_next_change_entry = <<END;
UPDATE file_changes
SET operation = $ADD_OPERATION
WHERE
    backup_id = $quoted_next_id AND
    seen_files_id IN (SELECT seen_files_id FROM file_changes WHERE backup_id = $quoted_backup_id);
END

            $dbh->do($update_next_change_entry);

            # Just need to remove the remainder.. that happens below
        }
        else {
            # Pruning most recent backup (or last backup)
            # remove all changes for it. (happens below)
        }
    }

    # If this is the last backup
    elsif ( !length $next_id ) {

        # Pruning the last in order backup
        # remove all changes for it. (happens below)
    }
    else {
        die "The system encountered an unknown state when pruning the backup with path $backup_dir.";
    }

    # Remove the remaining entries
    my $sth = $dbh->prepare(qq{DELETE FROM file_changes WHERE backup_id = ?;});
    $sth->execute($backup_id);
    $sth->finish();

    $sth = $dbh->prepare(qq{DELETE FROM backups WHERE backup_id = ?;});
    $sth->execute($backup_id);
    $sth->finish();

    $sth = $dbh->prepare(qq{DELETE FROM backup_paths WHERE backup_id = ?;});
    $sth->execute($backup_id);
    $sth->finish();

    #Reap dead seen_files
    $dbh->do("DELETE FROM seen_files WHERE file_id NOT IN (SELECT DISTINCT(seen_files_id) FROM file_changes);");

    return;
}

1;
