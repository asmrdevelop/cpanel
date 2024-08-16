package Cpanel::Backup::Restore;

# cpanel - Cpanel/Backup/Restore.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

################################################################################

use strict;
use warnings;

use Try::Tiny;

use Cpanel::AccessIds               ();
use Cpanel::Backup::Config          ();
use Cpanel::Backup::Metadata        ();
use Cpanel::Backup::MetadataDB      ();
use Cpanel::Backup::StreamFileList  ();
use Cpanel::Backup::Restore::Filter ();
use Cpanel::Exception               ();
use Cpanel::Locale                  ();
use Cpanel::PwCache                 ();
use Cpanel::SafeSync::UserDir       ();
use Cpanel::StatMode                ();

use Cwd            ();
use File::Basename ();
use Capture::Tiny  ();
use MIME::Base64   ();

*filter_stderr = *Cpanel::Backup::Restore::Filter::filter_stderr;

my $locale;

=encoding utf-8

=head1 NAME

Cpanel::Backup::Restore - This code does the heavy lifting for the cPanel API for
                          browsing and restoring backups.

=head1 SYNOPSIS

    use Cpanel::Backup::Restore;

    my $array_ref = Cpanel::Backup::Restore::directory_listing ('abc1', '/public_html/');
    my $array_ref = Cpanel::Backup::Restore::query_file_info ('abc1', '/public_html/index.php');


=head1 DESCRIPTION

This module contains functions for browsing backups on behalf of a user.

=cut

=head2 directory_listing

Returns a list of files and sub directories in all of this user's backups.  The
resulting list of files and dirs are union of all files and dirs in all of the
backups.

=over 2

=item Input

=back

=over 3

=item user (required) - The user who's backups you wish to get the directory listing

=back

=over 3

=item path (required) - The path in the backup to get a listing

path - must begin and end with a slash.  path of / means the
files and dirs in the users homedir.

=back

=over 2

=item Output

    • [root@julian64:/usr/local/cpanel] (HB-2800)# perl -MData::Dumper -MCpanel::Backup::Restore -e 'print Dumper (Cpanel::Backup::Restore::directory_listing ("abc1", "/withsubdirs/"));'
    $VAR1 = [
          {
            'name' => 'Xhowdy2.txt',
            'exists' => 1,
            'conflict' => 0,
            'type' => 'file',
            'onDiskType' => 'file'
          },
          {
            'type' => 'file',
            'conflict' => 0,
            'onDiskType' => 'file',
            'exists' => 1,
            'name' => 'howdy1.txt'
          },
          {
            'name' => 'howdy3.txt',
            'exists' => 1,
            'onDiskType' => 'file',
            'conflict' => 0,
            'type' => 'file'
          },
          {
            'name' => 'subdir1',
            'exists' => 1,
            'conflict' => 0,
            'type' => 'dir',
            'onDiskType' => 'dir'
          }
        ];

=back

=cut

sub _stat_as_user {
    my ( $lookup_ref, $user, $user_homedir ) = @_;

    my $base     = $user . '/homedir';
    my $base_len = length($base);

    my @output;
    @output = Cpanel::AccessIds::do_as_user_with_exception(
        $user,
        sub {
            foreach my $file ( keys %{$lookup_ref} ) {
                my $ref      = $lookup_ref->{$file};
                my $hr       = $ref->{'type_hash'};
                my $fullname = $ref->{'fullname'};
                my $fullpath = $user_homedir . $fullname;

                # TODO: better place to unescape the escaped things ?
                my $file_type = Cpanel::StatMode::filetype($fullpath);
                if ( !defined $file_type ) {
                    $ref->{'exists'}     = 0;
                    $ref->{'onDiskType'} = 'Unknown';
                }
                else {
                    $ref->{'exists'}     = 1;
                    $ref->{'onDiskType'} = $file_type;
                    $ref->{'conflict'}   = 1 if $file_type ne $ref->{'type'};
                }

                foreach my $file_type ( keys %{$hr} ) {
                    my $bref = {%$ref};
                    $bref->{'type'} = $file_type;
                    delete $bref->{'type_hash'} if exists $bref->{'type_hash'};
                    delete $bref->{'fullname'}  if exists $bref->{'fullname'};
                    push( @output, $bref );
                }
            }

            return @output;
        }
    );

    return @output;
}

sub _directory_listing_validate_parms {
    my ( $user, $path, $paginate ) = @_;

    my ( $code, $msg ) = Cpanel::Backup::Metadata::metadata_disabled_check();
    if ($code) {
        die Cpanel::Exception::create_raw( 'Unsupported', $msg );
    }

    $path //= '/';

    die Cpanel::Exception::create( 'MissingParameter', 'The system requires a username.' ) if !defined $user;

    if ( $user =~ m/\0/ || $path =~ m/\0/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Null bytes detected in input arguments.' );
    }

    # Make sure we are called by/for a legit user
    my $user_homedir = Cpanel::PwCache::gethomedir($user);
    die Cpanel::Exception::create( 'InvalidParameter', 'The path [output,strong,must] begin with a forward slash (/).' ) if ( !$user_homedir );

    # Make sure path begins and ends with a forward slash
    die Cpanel::Exception::create( 'InvalidParameter', 'The path [output,strong,must] begin with a forward slash (/).' ) if ( substr( $path, 0,                 1 ) ne '/' );
    die Cpanel::Exception::create( 'InvalidParameter', 'The path [output,strong,must] end with a forward slash (/).' )   if ( substr( $path, length($path) - 1, 1 ) ne '/' );

    if ( $paginate && $paginate ne 'NOPAGE' ) {
        $paginate->{'_page'} //= 0;

        #XXX we can't validate the size or start due to them being 'coerced' in Cpanel::Args to be default values for compatibility purposes.
        die Cpanel::Exception::create( 'InvalidParameter', 'You [output,strong,must] enter a nonnegative integer for the “[_1]” parameter.', ['api.paginate_page'] ) if !( $paginate->{'_page'} !~ tr{0-9}{}c ) || abs( $paginate->{'_page'} ) != int( $paginate->{'_page'} );
    }

    return $user_homedir;
}

sub directory_listing {
    my ( $user, $path, $paginate ) = @_;

    my $user_homedir = _directory_listing_validate_parms( $user, $path, $paginate );

    my $dbh = Cpanel::Backup::MetadataDB->dbconnect( user => $user, check_exists => 1 );

    my $path_len = length($path);
    my $sth;
    my $total_records = 0;

    my $common_query = qq{
        SELECT
            s.path AS name,
            (SELECT GROUP_CONCAT(type) FROM (SELECT distinct(type) FROM file_changes WHERE seen_files_id=s.file_id AND operation IN (1,0))) AS group_type
        FROM
            seen_files AS s
        WHERE
            s.path LIKE ? AND
            s.path NOT LIKE ?
        ORDER BY path ASC
    };

    if ( !$paginate || $paginate eq 'NOPAGE' ) {
        $sth = $dbh->prepare($common_query);
        $sth->execute( $path . "_%", "$path%/_%" );
    }
    else {
        #TODO we need to cache the count, way too expensive
        $sth = $dbh->prepare(
            qq{
            SELECT
                count(1)
            FROM
                seen_files AS s
            WHERE
                s.path LIKE ? AND
                s.path NOT LIKE ?
        }
        );
        $sth->execute( $path . "_%", "$path%/_%" );

        my $ref = $sth->fetchrow_arrayref();
        if ($ref) {
            $total_records = $ref->[0];
        }
        $sth->finish();

        my $_start           = $paginate->{'_start'};
        my $_size            = $paginate->{'_size'};
        my $_page            = $paginate->{'_page'};
        my $offset           = $_start + ( $_size * $_page );
        my $records_adjusted = $total_records - $_start;
        my $pages_ceil       = int( $records_adjusted / $_size ) + ( ( $records_adjusted % $_size ) ? 1 : 0 );

        #Check if the user's paginate request is valid
        if ( $total_records > 0 ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The page number “[_1]” does not exist. Only “[_2]” pages exist.', [ $_page, $pages_ceil ] ) if $offset >= $total_records;
        }
        else {
            return { 'total_records' => $total_records, 'records' => [] };
        }

        $sth = $dbh->prepare(
            qq{
            $common_query
            LIMIT ? OFFSET ?
        }
        );
        $sth->execute( $path . "_%", "$path%/_%", $_size, $offset );
    }

    my %lookup;
    my $row_refs = 1;
    while ( $row_refs = $sth->fetchall_arrayref( {}, 10000 ) ) {
        foreach my $ref ( @{$row_refs} ) {
            my @group_types = split( /,/, $ref->{'group_type'} );
            foreach my $type (@group_types) {
                $ref->{'type'} = $type;

                my $name = substr( $ref->{'name'}, $path_len );
                next if $name eq '';

                if ( $ref->{'type'} == 1 ) {
                    my $dname = substr( $name, 0, length($name) - 1 );
                    if ( index( $dname, '/' ) >= 0 ) {
                        next;
                    }

                    if ( substr( $name, length($name) - 1 ) eq '/' ) {
                        $name = substr( $name, 0, length($name) - 1 );
                    }
                }
                else {
                    if ( index( $name, '/' ) >= 0 ) {
                        next;
                    }
                }

                my $this_type = Cpanel::Backup::Metadata::translate_file_type( $ref->{'type'} );

                my $xref = {
                    'fullname'  => $ref->{'name'},        # needed by stat_as_user ()
                    'name'      => $name,
                    'conflict'  => 0,
                    'type_hash' => { $this_type => 1 },
                    'type'      => $this_type
                };

                my $yref = $lookup{ $ref->{'name'} };
                if ( defined $yref ) {
                    if ( $yref->{'type'} ne $xref->{'type'} ) {
                        $xref                              = {%$yref};
                        $xref->{'type'}                    = 'mixed';
                        $xref->{'type_hash'}->{$this_type} = 1;
                        $xref->{'conflict'}                = 1;
                    }
                }
                $lookup{ $ref->{'name'} } = $xref;
            }
        }
    }

    if ( !%lookup ) {
        if ( $path eq '/' ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'This account does not appear to have any usable backups.' );
        }
        elsif ( substr( $path, length($path) - 1 ) eq '/' ) {

            # This was an empty directory
        }
        else {
            die Cpanel::Exception::create( 'InvalidParameter', '[_1] does not exist.', [$path] );
        }
    }

    my @output = _stat_as_user( \%lookup, $user, $user_homedir );

    my $response_to_caller = { 'total_records' => $total_records, 'records' => \@output };

    return $response_to_caller;
}

=head2 query_file_info

Returns a list of all backups the specified file is in and stats about that file
in each of those backups.

=over 2

=item Input

=back

=over 3

=item user (required) - The user who's backups you wish to get the file info

=back

=over 3

=item path (required) - The path to the file in backups.

path - must begin slash.

=back

=over 2

=item Output

    • [root@julian64:/usr/local/cpanel] (HB-2800)# perl -MData::Dumper -MCpanel::Backup::Restore -e 'print Dumper (Cpanel::Backup::Restore::query_file_info ("abc1", "/public_html/index.php"));'
    $VAR1 = [
          {
            'type' => 'file',
            'path' => '/public_html/index.php',
            'mtime' => 11111111111,
            'backupID' => 'monthly/2017-07-15',
            'backupDate' => '2017-07-15'
          },
          {
            'path' => '/public_html/index.php',
            'type' => 'file',
            'backupID' => 'weekly/2017-07-30',
            'backupDate' => '2017-07-30',
            'mtime' => 11111111111,
          },
          {
            'path' => '/public_html/index.php',
            'type' => 'file',
            'mtime' => 11111111111,
            'backupDate' => '2017-07-25',
            'backupID' => '2017-07-25'
          },
          {
            'type' => 'file',
            'path' => '/public_html/index.php',
            'backupDate' => '2017-07-27',
            'backupID' => '2017-07-27',
            'mtime' => 11111111111,
          },

          ...

=back

=cut

sub _get_backup_path {
    my ($backup_path) = @_;

    if ( $backup_path =~ m/^(.+)\/accounts$/ ) {
        $backup_path = $1;
    }

    return $backup_path;
}

sub _prepare_out_record {
    my ( $ref, $user, $master_meta, $fullpath, $backup_dir ) = @_;

    $ref->{'backup_dir'} = _get_backup_path( $ref->{'backup_path'} );

    my $out_ref = {};

    my $backupID;
    $backupID = substr( $ref->{'backup_dir'}, length($backup_dir) + 1 );

    $out_ref->{'backupID'}    = $backupID;
    $out_ref->{'backup_path'} = $ref->{'backup_dir'};
    $out_ref->{'path'}        = $fullpath;

    $out_ref->{'fileSize'} = $ref->{'size'} if exists $ref->{'size'} && $ref->{'type'} == Cpanel::Backup::Metadata::METADATA_ENTRY_TYPE_FILE;

    #Should be the same value as $meta_master_fname in Cpanel::Backup::Metadata::load_master_meta
    die Cpanel::Exception::create(
        'UserdataLookupFailure',
        'The system could not find data in the “[_1]” file for user “[_2]”. To create data for this user, your system administrator must run the “/usr/local/cpanel/scripts/backups_create_metadata --all” command.', [ Cpanel::Backup::Metadata::master_meta_file($backup_dir), $user ]
    ) if ref $master_meta->{users} ne 'HASH' || ref $master_meta->{users}->{$user} ne 'HASH';
    $out_ref->{'backup_type'} = $master_meta->{'users'}->{$user}->{'backup_type'};
    $out_ref->{'type'}        = $ref->{'type'};

    $out_ref->{'mtime'} = $ref->{'mtime'};

    return $out_ref;
}

sub _fill_in_backups {
    my (%opts) = @_;

    my $base_ref        = $opts{'base_ref'};
    my $user            = $opts{'user'};
    my $master_meta     = $opts{'master_meta'};
    my $dbh             = $opts{'dbh'};
    my $fullpath        = $opts{'path'};
    my $backup_dir      = $opts{'backup_dir'};
    my $after_backup_id = $opts{'after_backup_id'};
    my $until_backup_id = $opts{'until_backup_id'};

    my @output;
    my $sth;

    if ($until_backup_id) {
        $sth = $dbh->prepare(
            qq{SELECT bp.backup_path, b.timestamp, b.backup_id
            FROM backups AS b
            JOIN backup_paths AS bp ON b.backup_id = bp.backup_id
            WHERE b.backup_id > ? AND b.backup_id < ?;}
        );
        $sth->execute( $after_backup_id, $until_backup_id );
    }
    else {
        $sth = $dbh->prepare(
            qq{SELECT bp.backup_path, b.timestamp, b.backup_id
            FROM backups AS b
            JOIN backup_paths AS bp ON b.backup_id = bp.backup_id
            WHERE b.backup_id > ?;}
        );
        $sth->execute($after_backup_id);
    }

    while ( my $ref = $sth->fetchrow_hashref() ) {
        my $backup_path             = _get_backup_path( $ref->{'backup_path'} );
        my $master_meta_this_backup = Cpanel::Backup::Metadata::load_master_meta($backup_path);

        my $record_ref = {
            'size'        => $base_ref->{'size'},
            'mtime'       => $base_ref->{'mtime'},
            'path'        => $base_ref->{'path'},
            'type'        => $base_ref->{'type'},
            'backup_path' => $backup_path,
            'timestamp'   => $ref->{'timestamp'},
            'backup_id'   => $ref->{'backup_id'},
        };

        push( @output, _prepare_out_record( $record_ref, $user, $master_meta_this_backup, $fullpath, $backup_dir ) );
    }

    return @output;
}

sub _get_fullpath_records {
    my ( $user, $fullpath ) = @_;

    # Allow for directories to have a trailing slash. We remove it here for the sql query to match what's in the DB.
    if ( $fullpath ne '/' && substr( $fullpath, length($fullpath) - 1 ) eq '/' ) {
        $fullpath = substr( $fullpath, 0, length($fullpath) - 1 );
    }
    my $backup_dir = Cpanel::Backup::Metadata::_get_backup_master_dir();

    my $user_homedir = Cpanel::PwCache::gethomedir($user);

    my $dbh = Cpanel::Backup::MetadataDB->dbconnect( user => $user, check_exists => 1 );
    my $sth;

    if ( $fullpath eq '/' ) {
        $sth = $dbh->prepare(
            qq{
            SELECT
                0 AS size,
                0 AS mtime,
                "/" AS path,
                1 AS type,
                bp.backup_path,
                0 AS operation,
                b.timestamp,
                b.backup_id
            FROM backups as b
            JOIN backup_paths AS bp ON bp.backup_id = b.backup_id
            }
        );
        $sth->execute();
    }
    else {
        $sth = $dbh->prepare(
            qq{
            SELECT
                f.size,
                f.mtime,
                s.path,
                f.type,
                bp.backup_path,
                f.operation,
                b.timestamp,
                b.backup_id
            FROM file_changes AS f
            JOIN seen_files AS s ON file_id=f.seen_files_id
            JOIN backups AS b ON b.backup_id = f.backup_id
            JOIN backup_paths AS bp ON bp.backup_id = b.backup_id
            WHERE path = ?
        }
        );
        $sth->execute($fullpath);
    }

    my @output;

    my $prev_ref;
    while ( my $ref = $sth->fetchrow_hashref() ) {
        my $backup_path = _get_backup_path( $ref->{'backup_path'} );
        $ref->{'backup_dir'} = $backup_path;

        my $master_meta = Cpanel::Backup::Metadata::load_master_meta($backup_path);

        if ($prev_ref) {
            push(
                @output,
                _fill_in_backups(
                    'base_ref'        => $prev_ref,
                    'user'            => $user,
                    'master_meta'     => $master_meta,
                    'dbh'             => $dbh,
                    'path'            => $fullpath,
                    'backup_dir'      => $backup_dir,
                    'after_backup_id' => $prev_ref->{'backup_id'},
                    'until_backup_id' => $ref->{'backup_id'}
                )
            );
        }

        if ( $ref->{'operation'} == 2 ) {
            undef $prev_ref;
            next;
        }

        # if it has backup_type and it is eq ERROR
        # than this backup does not exist on the disk
        if ( exists $master_meta->{'backup_type'} && $master_meta->{'backup_type'} eq 'ERROR' ) {
            $prev_ref = $ref;
            next;
        }

        if ( $ref->{'backup_path'} =~ m/\Q$backup_dir\E\/(.+)\/accounts/ ) {
            push( @output, _prepare_out_record( $ref, $user, $master_meta, $fullpath, $backup_dir ) );
            $prev_ref = $ref;
        }
    }

    if ($prev_ref) {
        my $master_meta = Cpanel::Backup::Metadata::load_master_meta( $prev_ref->{'backup_dir'} );
        push(
            @output,
            _fill_in_backups(
                'base_ref'        => $prev_ref,
                'user'            => $user,
                'master_meta'     => $master_meta,
                'dbh'             => $dbh,
                'path'            => $fullpath,
                'backup_dir'      => $backup_dir,
                'after_backup_id' => $prev_ref->{'backup_id'},
                'until_backup_id' => undef
            )
        );
    }

    return @output;
}

sub _rename_hash_key {
    my ( $ref, $oldkey, $newkey ) = @_;

    return if !exists $ref->{$oldkey};

    $ref->{$newkey} = $ref->{$oldkey};
    delete $ref->{$oldkey};

    return;
}

sub _file_exists_as_user {
    my ( $user, $user_homedir, $path ) = @_;

    my $exists = 0;
    $exists = Cpanel::AccessIds::do_as_user_with_exception(
        $user,
        sub {
            my $fullpath = $user_homedir . $path;

            if ( -e $fullpath ) {
                $exists = 1;
            }

            return $exists;
        }
    );

    return $exists;
}

sub query_file_info {
    my ( $user, $fullpath, $return_exists_flag_to_caller ) = @_;

    my ( $code, $msg ) = Cpanel::Backup::Metadata::metadata_disabled_check();
    if ($code) {
        die Cpanel::Exception::create_raw( 'Unsupported', $msg );
    }

    die Cpanel::Exception::create( 'MissingParameter', 'The system requires a username.' )                               if !defined $user;
    die Cpanel::Exception::create( 'MissingParameter', 'The system requires a path.' )                                   if !defined $fullpath;
    die Cpanel::Exception::create( 'InvalidParameter', 'The path [output,strong,must] begin with a forward slash (/).' ) if ( substr( $fullpath, 0, 1 ) ne '/' );

    if ( $user =~ m/\0/ || $fullpath =~ m/\0/ || $fullpath =~ m/\/\.\.\// ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Invalid data detected in input arguments.' );
    }

    my $user_homedir = Cpanel::PwCache::gethomedir($user);
    die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system could [output,strong,not] find the username.' ) if ( !defined $user_homedir );

    $return_exists_flag_to_caller //= 0;

    my @output = _get_fullpath_records( $user, $fullpath );

    my $path_exists;

    foreach my $ref (@output) {
        my $backup_path = $ref->{'backup_path'};
        my ( $year, $mon, $day ) = $backup_path =~ m/(\d{4})-(\d{2})-(\d{2})/a;

        $ref->{'backupDate'} = "$year-$mon-$day";

        delete $ref->{'backup_path'};
        _rename_hash_key( $ref, 'backup_type', 'backupType' );

        if ($return_exists_flag_to_caller) {
            if ( !defined $path_exists ) {
                $path_exists = _file_exists_as_user( $user, $user_homedir, $ref->{'path'} );
            }

            $ref->{'exists'} = $path_exists;
        }
    }

    die Cpanel::Exception::create( 'InvalidParameter', '[_1] does not exist.', [$fullpath] ) if !@output;
    return \@output;
}

sub _deal_with_incremental {
    my ($collection) = @_;

    my $user       = $collection->{'user'};
    my $backupPath = $collection->{'backupPath'};    # /backup/monthly/2017-07-01
    my $backupID   = $collection->{'backupID'};      # monthly/2017-07-01
    my $fullpath   = $collection->{'path'};          # /public_html/index.php
    my $overwrite  = $collection->{'overwrite'};
    my $record     = $collection->{'record'};

    my $user_homedir = Cpanel::PwCache::gethomedir($user);
    die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system could [output,strong,not] find the username.' ) if ( !defined $user_homedir );

    if ( $user =~ m/\0/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Invalid data detected in input arguments.' );
    }

    # Protect against users trying to restore what was a symlink to a directory/file

    my $basepath     = $backupPath . '/accounts/' . ${user} . '/homedir';
    my $backup_fname = $basepath . $fullpath;

    die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system could not find the backup file.' ) if ( !-l $backup_fname && !-e _ );

    if ( $record->{'type'} != 1 ) {
        my $real_path = $user_homedir . $fullpath;
        if ( -e $real_path && $overwrite == 0 ) {
            die Cpanel::Exception::create( 'EntryAlreadyExists', 'The file already exists but you [output,strong,must] set the overwrite flag to 1 to restore the file.' );
        }
    }

    my ( $target_user_uid, $target_user_gid, $user_home_dir ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3, 7 ];

    # Check to ensure that the given path is inside the user's system home directory
    my $target = $user_homedir . File::Basename::dirname($fullpath);
    $target = $user_homedir if ( $record->{'type'} == 1 );
    if ( $target !~ m/^$user_home_dir/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Invalid data detected in input arguments.' );
    }

    my @stderr = Capture::Tiny::capture_stderr(
        sub {
            my $return = Cpanel::SafeSync::UserDir::restore_to_userdir(
                'source'                => $backup_fname,
                'target'                => $target,
                'base_dir'              => $basepath,
                'from_restore'          => 1,
                'setuid'                => [ $target_user_uid, $target_user_gid ],
                'wildcards_match_slash' => 0,
                'overwrite'             => $overwrite,
            );
        }
    );
    pop(@stderr);    # drop the 1 returned from capture_stderr
    if (@stderr) {
        my $stderr_ar = Cpanel::Backup::Restore::Filter::filter_stderr( \@stderr );
        if ( @{$stderr_ar} ) {
            $locale ||= Cpanel::Locale->get_handle();
            print STDERR $locale->maketext( 'The system detected problems when it tried to restore the “[_1]” backup for the “[_2]” file. “[_3]”.', $backup_fname, $target, @{$stderr_ar} ) . "\n";
            return ( 0, $stderr_ar );
        }
    }
    return ( 1, undef );
}

sub _deal_with_tarball {
    my ($collection) = @_;

    my $user       = $collection->{'user'};
    my $backupPath = $collection->{'backupPath'};
    my $backupID   = $collection->{'backupID'};     # monthly/2017-07-01
    my $fullpath   = $collection->{'path'};
    my $overwrite  = $collection->{'overwrite'};
    my $record     = $collection->{'record'};

    my $user_homedir = Cpanel::PwCache::gethomedir($user);
    die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system could [output,strong,not] find the username.' ) if ( !defined $user_homedir );

    if ( $user =~ m/\0/ ) {

        die Cpanel::Exception::create( 'InvalidParameter', 'Invalid data detected in input arguments.' );
    }

    my $fullname = "${user}/homedir" . $fullpath;

    if ( $record->{'type'} != 1 ) {
        my $real_path = $user_homedir . $fullpath;
        if ( -e $real_path && $overwrite == 0 ) {
            die Cpanel::Exception::create( 'EntryAlreadyExists', 'The file already exists but you [output,strong,must] set the overwrite flag to 1 to restore the file.' );
        }
    }

    my $backup_tarball;
    if ( $record->{'backup_type'} == 1 ) {    # compressed
        $backup_tarball = $backupPath . '/accounts/' . $user . '.tar.gz';
    }
    elsif ( $record->{'backup_type'} == 0 ) {    # uncompressed
        $backup_tarball = $backupPath . '/accounts/' . $user . '.tar';
    }
    else {
        die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system could [output,strong,not] find the backup file.' );
    }

    if ( $backup_tarball !~ m{^\Q${backupPath}/accounts/${user}.tar\E(|\.gz)$} ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Restoration asked to follow path outside of the home directory of the account.' );
    }

    my $real_tarball_path = Cwd::abs_path($backup_tarball);
    if ( $real_tarball_path ne $backup_tarball ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Restoration asked to follow path outside of the home directory of the account.' );
    }

    # If we don't have either a .tar or .tar.gz, but we are here because the backup type is compressed, wtfmate ?
    if ( !-f $backup_tarball ) {
        die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system could [output,strong,not] find the backup file.' );
    }

    my ( $target_user_uid, $target_user_gid, $user_home_dir ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3, 7 ];

    # Check to ensure that the given home directory path is in line with the user's actual system home directory
    if ( $user_homedir !~ m/^$user_home_dir/ ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Invalid data detected in input arguments.' );
    }

    my @stderr = Capture::Tiny::capture_stderr(
        sub {
            my $return = Cpanel::SafeSync::UserDir::restore_to_userdir(
                'tarballpath'           => $backup_tarball,
                'source'                => $fullname,
                'target'                => $user_homedir,
                'setuid'                => [ $target_user_uid, $target_user_gid ],
                'wildcards_match_slash' => 0,
                'overwrite'             => $overwrite,
                'from_restore'          => 1,
            );
        }
    );
    pop(@stderr);    # drop the 1 returned from capture_stderr
    if (@stderr) {
        my $stderr_ar = Cpanel::Backup::Restore::Filter::filter_stderr( \@stderr );
        if ( @{$stderr_ar} ) {

            # Send it to the error_log
            $locale ||= Cpanel::Locale->get_handle();
            print STDERR $locale->maketext( 'The system detected problems when it tried to restore the “[_1]” backup for the “[_2]” file. “[_3]”.', $backup_tarball, $user_homedir, @{$stderr_ar} ) . "\n";
            return ( 0, $stderr_ar );
        }
    }

    return ( 1, undef );
}

=head2 restore_file

Restores a file from backup.

=over 2

=item Input

=back

=over 3

=item user (required) - The user who's backups you wish to restore the file from.

=back

=over 3

=item backupPath (required) - The path to the top of the backup.

backupPath - must begin slash. e.g. /backup/2017-07-02

=back

=over 3

=item path (required) - The path to the file in backups.

fullpath - must begin slash.

=back

=over 3

=item overwrite (required) - Allows you to overwrite an existing file.

overwrite - 1 or 0, 1 allows the file to be overwritten if it currently exists in the filesystem.

=back

=over 2

=item Output

    success = 1

=back

=cut

sub restore_file {
    my ( $user, $backupID, $fullpath, $overwrite ) = @_;

    my ( $code, $msg ) = Cpanel::Backup::Metadata::metadata_disabled_check();
    if ($code) {
        die Cpanel::Exception::create_raw( 'Unsupported', $msg );
    }

    # Squash an duplicate forward slashes, while they might be technically legal, they servce no purpose and mess up our counting of directories to strip
    $fullpath =~ s/\/+/\// if defined $fullpath;

    die Cpanel::Exception::create( 'MissingParameter', 'The system requires a username.' )   if !defined $user;
    die Cpanel::Exception::create( 'MissingParameter', 'The system requires a backup id.' )  if !defined $backupID;
    die Cpanel::Exception::create( 'MissingParameter', 'The system requires a path.' )       if !defined $fullpath;
    die Cpanel::Exception::create( 'MissingParameter', 'The system requires an overwrite.' ) if !defined $overwrite;

    die Cpanel::Exception::create( 'InvalidParameter', 'The path [output,strong,must] begin with a forward slash (/).' ) if ( substr( $fullpath, 0, 1 ) ne '/' );
    die Cpanel::Exception::create( 'InvalidParameter', 'Set the overwrite flag to 1 or 0.' )                             if ( $overwrite != 0 && $overwrite != 1 );

    my ( $target_user_uid, $target_user_gid ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3 ];
    if ( !defined($target_user_uid) || !defined($target_user_gid) ) {
        die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system requires an existing user to restore to.' );
    }

    my $backup_conf = Cpanel::Backup::Config::load();
    my $backup_dir  = $backup_conf->{'BACKUPDIR'};

    my $backupPath = Cpanel::Backup::StreamFileList::get_backup_path_from_backup_id( $backup_dir, $backupID );
    die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system could [output,strong,not] find the backup path.' ) if ( !defined $backupPath );

    my @records = _get_fullpath_records( $user, $fullpath );
    my $record;

    foreach my $xrecord (@records) {
        if ( $backupPath eq $xrecord->{'backup_path'} ) {
            $record = $xrecord;
            last;
        }
    }

    die Cpanel::Exception::create( 'EntryDoesNotExist', 'The system could not find the backup path.' ) if ( !defined $record );

    my $collection = {
        'user'       => $user,
        'backupID'   => $backupID,
        'backupPath' => $backupPath,
        'path'       => $fullpath,
        'overwrite'  => $overwrite,
        'record'     => $record,
    };

    my ( $ret, $msg_ar );

    if ( $record->{'backup_type'} == 2 ) {    # incremental
        ( $ret, $msg_ar ) = _deal_with_incremental($collection);
    }
    else {
        ( $ret, $msg_ar ) = _deal_with_tarball($collection);
    }

    if ( $ret == 0 ) {
        die Cpanel::Exception::create( 'Backup::RestoreFailed', "The system encountered an error during the attempt to restore the file. For details, check this error log, or contact your hosting provider: /usr/local/cpanel/logs/error_log ." );
    }

    my $response_to_caller = {
        'success' => 1,
    };

    return $response_to_caller;
}

1;
