package Cpanel::Logs;

# cpanel - Cpanel/Logs.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

## no critic(TestingAndDebugging::RequireUseWarnings) -- This is older code and has not been tested for warnings safety yet.
use strict;

use Fcntl      ();
use IPC::Open3 ();

use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::EA4::Constants               ();
use Cpanel::Gzip::Stream                 ();
use Cpanel::Logger                       ();
use Cpanel::Logs::Find                   ();
use Cpanel::Logs::Truncate               ();
use Cpanel::Mkdir                        ();
use Cpanel::PwCache                      ();
use Cpanel::SafeDir::MK                  ();
use Cpanel::Sys::Chattr                  ();
use Cpanel::WildcardDomain               ();
use File::Basename                       ();

our $VERSION = '1.7';

our $OPTIMAL_READ_SIZE_FOR_LARGE_LOGS = 262144;

my @MonthName = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);

# Constants
our $DO_ARCHIVE = 1;
our $NO_ARCHIVE = 0;

*find_wwwaccesslog        = *Cpanel::Logs::Find::find_wwwaccesslog;
*find_ftpaccesslog        = *Cpanel::Logs::Find::find_ftpaccesslog;
*find_sslaccesslog        = *Cpanel::Logs::Find::find_sslaccesslog;
*find_wwwerrorlog         = *Cpanel::Logs::Find::find_wwwerrorlog;
*find_byteslog            = *Cpanel::Logs::Find::find_byteslog;
*find_byteslog_backup     = *Cpanel::Logs::Find::find_byteslog_backup;
*find_popbyteslog         = *Cpanel::Logs::Find::find_popbyteslog;
*find_imapbyteslog        = *Cpanel::Logs::Find::find_imapbyteslog;
*find_popbyteslog_backup  = *Cpanel::Logs::Find::find_popbyteslog_backup;
*find_imapbyteslog_backup = *Cpanel::Logs::Find::find_imapbyteslog_backup;
*find_ftpbyteslog         = *Cpanel::Logs::Find::find_ftpbyteslog;
*find_ftplog              = *Cpanel::Logs::Find::find_ftplog;
*find_logbyext            = *Cpanel::Logs::Find::find_logbyext;
*update_log_locations     = *Cpanel::Logs::Find::update_log_locations;

#
# Copy data from $logfile to the stream attached to $fh. Because it is intended
# for use with logfiles, logsnip will copy all lines of the file to the line that
# ends on or after $snipbyte.
sub logsnip {
    my ( $logfile, $snipbyte, $fh ) = @_;
    $snipbyte = int($snipbyte);
    my $snipping = 1;
    my $pos      = 0;
    my $buffer;

    if ( !defined($logfile) || !defined($snipbyte) || !defined($fh) ) {
        my $logger = Cpanel::Logger->new();
        $logger->warn("Cpanel::Logs::logsnip: usage <logfile> <snipbyte> <file handle>");
        return;
    }

    open( my $log_fh, '<', $logfile ) || do {
        my $logger = Cpanel::Logger->new();
        $logger->warn("Cpanel::Logs::logsnip: Could not open $logfile for reading: $!");
        return;
    };
    while ($snipping) {
        my $rc = read( $log_fh, $buffer, 16384 );
        if ( !defined($rc) ) {
            my $logger = Cpanel::Logger->new();
            $logger->warn("Cpanel::Logs::logsnip: Fatal error in read");
            return;
        }
        $pos += $rc;
        last if $rc == 0;

        if ( $snipbyte == 0 || $pos <= $snipbyte ) {
            print {$fh} $buffer;
        }
        else {
            $pos -= $rc;
            for my $line ( split( /\n/, $buffer ) ) {
                print {$fh} $line . "\n";
                $pos += length($line) + 1;
                if ( $pos >= $snipbyte ) {
                    $snipping = 0;
                    last;
                }
            }
            last if !$snipping;
        }
    }
    close $log_fh;

    return;
}

#
# Find all recognizable bytes files in all of the log directories and
# rename them to bkup versions.
#
# Takes an optional array ref containing domains to further filter the list
#  of bytes files to backup.
sub backup_http_bytes_logs {
    my ($domains_ar) = @_;
    return unless defined $domains_ar;
    my $logger = Cpanel::Logger->new();

    my $changed = 0;

    # Process each domain
    foreach my $dom ( @{$domains_ar} ) {
        my $safe_dom = Cpanel::WildcardDomain::encode_wildcard_domain($dom);
        my $file     = find_byteslog($safe_dom);

        $changed = 1 if backup_byteslog( $logger, $file, find_byteslog_backup($safe_dom) );
    }

    return $changed;
}

#
# Backup all imap/pop bytes logs in all of the log directories for the supplied user
sub backup_pop_imap_bytes_logs {
    my ($user) = @_;
    return unless defined $user;
    my $logger = Cpanel::Logger->new();

    my $changed = 0;
    $changed = 1 if backup_byteslog( $logger, find_popbyteslog($user),  find_popbyteslog_backup($user) );
    $changed = 1 if backup_byteslog( $logger, find_imapbyteslog($user), find_imapbyteslog_backup($user) );

    return $changed;
}

sub backup_byteslog {
    my ( $logger, $file, $bak ) = @_;
    return unless length $file and -s $file;

    my $changed = 0;
    if ( length $bak ) {
        if ( -z $bak ) {

            # Discard 0-length backup files.
            # This shouldn't happen. But if it does, don't move it.
            unlink($bak);
        }
        else {

            # On the odd chance that backup has not been processed,
            # move the current backup to a second backup.
            my $bak2 = "${bak}2";
            rename( $bak, $bak2 ) or $logger->warn("'$bak' rename to '$bak2' failed: $!");
            $changed = 1;
        }
    }

    # backup only bytes files.
    my $new = backup_filename($file);
    rename( $file, $new ) or $logger->warn("'$file' rename to '$new' failed: $!");
    $changed = 1;

    return $changed;
}

#
# Finds all recognizable bytes files in all of the log directories and
# returns a list of those filenames
#
# Takes an optional array ref containing domains to further filter the list
#  of bytes files to backup.
sub list_http_bytes_logs {
    my ($domains_ar) = @_;
    my $domain_re =
      defined $domains_ar
      ? '(?:' . join( '|', map { "\Q$_\E" } @{$domains_ar} ) . ')'
      : '.*?';
    $domain_re = qr/$domain_re/;
    my @bytes_files = ();

    Cpanel::Logs::Find::update_log_locations() unless @Cpanel::Logs::Find::_log_locations;
    foreach my $logdir (@Cpanel::Logs::Find::_log_locations) {
        opendir( my $dir, $logdir ) or next;
        my @files = grep { !/^..?$/ } readdir($dir);
        closedir($dir);

        # Remove anything that is not a byteslog or backup
        push @bytes_files, grep { /^(?:www\.)?${domain_re}-bytes_log(?:\.bkup2?)?$/ && -f "$logdir/$_" } @files;
    }

    my %seen = ();
    return grep { !$seen{$_}++ } @bytes_files;
}

# Find all of the logs that need processing. The function requires a list of domains
# It returns a list of logfile descriptors.
# Each descriptor is a hash with the following items:
#  logfile - the name of the logfile to process
#  domain - the domain associated with this log
#  dir - subdirectory for logs
#  filename - initial filename
sub list_logs_to_process {
    my (@domains)  = @_;
    my @logs       = ();
    my (@LOGTYPES) = ( [ '', '', '' ], [ '', '-ssl_log', '/ssl' ], );
    foreach my $dom (@domains) {
        foreach my $L (@LOGTYPES) {
            my ( $prefix, $ext, $dir ) = @{$L};
            my $domain     = $prefix . Cpanel::WildcardDomain::encode_wildcard_domain($dom);
            my $access_log = Cpanel::Logs::find_logbyext( $domain, $ext );

            # Handle backup file if no primary file.
            if ( !$access_log || $access_log eq '' || !-e $access_log || -d _ || -z _ ) {
                $access_log = Cpanel::Logs::find_logbyext( $domain, "$ext.bkup" );
                next if !$access_log || $access_log eq '' || !-e $access_log || -d _ || -z _;
                $access_log =~ s/\.bkup$//;    # Retrieve the actual name and not the bkup name.
            }
            my ($filename) = ( split /\//, $access_log )[-1];

            # handle special case for ssl logs.
            $domain = $1 if $access_log =~ m{/(\Qwww.$domain\E)-ssl_log};
            push @logs,
              {
                logfile  => $access_log,
                domain   => $domain,
                dir      => $dir,
                filename => $filename,
              };
        }
    }

    return @logs;
}

sub prepare_ftplog_for_processing {
    my ( $ftplog, $domain ) = @_;

    my ( $dir, $filename ) = $ftplog =~ m{^(.*)/([^/]+)$};

    return {
        'logfile'  => $ftplog,
        'domain'   => Cpanel::WildcardDomain::encode_wildcard_domain($domain),
        'dir'      => $dir,
        'filename' => $filename,
    };
}

#
# Given a list of file paths, generate a list of minimal log descriptors from them.
sub make_logdesc_list {
    my @logdesc = ();
    foreach my $logpath (@_) {
        my ($filename) = ( split /\//, $logpath )[-1];
        $filename =~ s/\.bkup$//;
        push @logdesc, { logfile => $logpath, filename => $filename };
    }
    return @logdesc;
}

#
# Copy the contents of the file named by C<$filename> into the C<$out_fh> file
# handle.
#
# The last location that was read will be stored in C<$filename.offset>. Subsequent
# copies begin from the stored offset.
#
# Returns true on success, false if C<$filename> doesn't exist and exceptions on failure.
sub copy_file_to_handle {
    my ( $filename, $out_fh ) = @_;

    return unless -e $filename;
    my $offset = 0;
    if ( open my $fh, '<', "$filename.offset" ) {
        $offset = <$fh>;
        close $fh;
    }
    $offset = 0 if $offset > -s $filename;    # reset if file was truncated.

    # The 'die's below are all exceptions, not logger things.
    # Only open the file if we have more to read.
    if ( $offset != -s $filename ) {
        open( my $in_fh, '<', $filename ) or die "Cannot open '$filename': $!\n";
        seek( $in_fh, $offset, 0 ) if $offset;
        my $line;
        while ( read( $in_fh, $line, $OPTIMAL_READ_SIZE_FOR_LARGE_LOGS ) ) {
            unless ( $out_fh->write($line) ) {
                die "Failed to write '$filename' to output: $!.\n";
            }
        }
        $offset = tell($in_fh);
        die "Unable to read file position '$filename': $!\n" if $offset < -1;
        close($in_fh);

        open my $fh, '>', "$filename.offset" or die "Unable to write offset file for '$filename'.\n";
        print $fh $offset;
        close $fh;
    }
    return 1;
}

#
# Compress the contents of the file C<$filename> into the C<$archive_file> archive.
# If successful, remove C<$filename> and return 1.
# Throw an exception on failure.
sub archive_file {
    my ( $filename, $archive_file, $user ) = @_;

    my $archive_fh;

    my $open_fh_code_ref = sub {
        return sysopen( $archive_fh, $archive_file, Fcntl::O_WRONLY() | Fcntl::O_APPEND() | Fcntl::O_CREAT() | Fcntl::O_NOFOLLOW() );
    };

    my $ret;
    if ( length $user && $> == 0 && $user ne 'root' ) {
        $ret = Cpanel::AccessIds::ReducedPrivileges::call_as_user( $open_fh_code_ref, $user );
    }
    else {
        $ret = $open_fh_code_ref->();
    }
    if ($ret) {
        local $Cpanel::Gzip::Stream::Z_COMPRESS_LEVEL = 6;
        my $orig_size = tell($archive_fh);
        my $zlib      = Cpanel::Gzip::Stream->new($archive_fh) || die "Could not create gzip stream to $archive_file: $!";
        my $success   = eval { copy_file_to_handle( $filename, $zlib ); };
        $zlib->close() == $Cpanel::Gzip::Stream::Z_OK or die "Failed write end of gzip stream while writing to: $filename";

        # Save any exception for later.
        my $ex = $@;
        if ( !$success ) {

            # Remove new data, since we'll rewrite it on the next try.
            truncate( $archive_fh, $orig_size );
            close $archive_fh;

            # if exception, propagate it.
            die $ex if $ex;
            die "Unable to archive backup file '$filename'.\n";
        }
        close $archive_fh;
    }
    return 1;
}

#
# Move the file named by C<$filename> to the name C<$bkup>. Recreate the file
# C<$filename> containing approximately the last C<$rotatesize> bytes from the
# original file (The difference in size is caused by dropping the partial line
# crossing the <$rotatesize> boundary.)
#
# Return one on success and exception on failure.
sub rotate_file {
    my ( $filename, $bkup, $rotatesize, $with_offset ) = @_;
    return if ( $rotatesize > 0 && -s $filename <= $rotatesize );

    link( $filename, $bkup ) or die "Failed to link '$filename' to '$bkup': $!";

    # Create rotated file.
    my $rotate_tmp_filename = $filename . "_rotate_tmp";
    eval { _rotate_file( $filename, $rotate_tmp_filename, $rotatesize / 2 ); };
    if ( my $ex = $@ ) {

        # If the following fails, we're pretty well stuck.
        # We have already determined we can't go forward, so now we go back.
        unlink( $bkup, $rotate_tmp_filename );
        die $ex;
    }
    die "Temporary log rotation file was not created." unless ( -e $rotate_tmp_filename );
    rename( $rotate_tmp_filename, $filename ) or die "Failed to rename new '$filename' in place: $!";

    if ($with_offset) {

        # Move real offset file to backup offset file name
        unlink "$bkup.offset" if -e "$bkup.offset";
        if ( !-e "$filename.offset" || rename( "$filename.offset", "$bkup.offset" ) ) {
            eval { _rotated_offset($filename); };
            if ( my $ex = $@ ) {

                # If the following fails, we're pretty well stuck.
                # We have already determined we can't go forward, and now we can't go back.
                rename( "$bkup.offset", "$filename.offset" );
                rename( $bkup,          $filename );
                die $ex;
            }
        }
        else {
            rename( $bkup, $filename );
            die "Unable to back up the offset file '$filename.offset': $!\n";
        }
    }
    return 1;
}

sub _rotate_file {
    my ( $orig_file, $new_file, $rotatesize ) = @_;
    my $logger   = Cpanel::Logger->new();
    my $log_perm = ( stat($orig_file) )[2] & 07777;

    sysopen( my $ofh, $new_file, Fcntl::O_WRONLY() | Fcntl::O_CREAT(), $log_perm ) or die "Unable to create '$new_file': $!\n";    ## no critic qw(Subroutines::ProhibitAmpersandSigils)
    if ($rotatesize) {
        open( my $fh, '<', $orig_file ) or die "Unable to open '$orig_file': $!\n";
        seek( $fh, -$rotatesize, 2 );
        my $buffer = <$fh>;                                                                                                        # discard the last of the previous line.
        while ( read( $fh, $buffer, 16 * 1024 ) ) {
            print $ofh $buffer;
        }
        close $fh;
    }
    close $ofh or die "Unable to finish writing '$new_file': $!\n";

    return;
}

sub _rotated_offset {
    my ($filename) = @_;

    my $size = -s $filename;
    return unless $size;

    open my $fh, '>', "$filename.offset" or die "Unable to create offset file '$filename.offset': $!\n";
    print $fh $size;
    close $fh or die "Unable to write the offset file '$filename.offset': $@\n";

    return;
}

#
# Given a list of filenames, generate a new list containing the names of the
# corresponding backup files.
sub make_backup_list {
    return map { "$_.bkup" } @_;
}

sub backup_filename {
    return "$_[0].bkup";
}

#
# Clean out debris from previous runs of the log processing.
sub clean_debris {
    my ($file) = @_;
    foreach my $ext (qw/.bkup .bkup2 .bkup.offset .bkup2.offset/) {
        unlink "$file$ext" if -e "$file$ext" && -z _;
    }
    return;
}

#
# Perform whatever pre-processing is needed based on the C<$postprocess> argument,
# on the files described by the C<$logs_ref> array of hashes.
#
# Return the number of files modified. Exception on failures.
#
# C<$procdesc> is a hash containing two keys, the values for 'type' can contain
# one of the following values:
#  sysarchive - compress the data in the file into the archive dir and delete
#               when finished
#  userarchive - compress the data in the file into the $HOME/logs dir and delete
#               when finished
#  delete     - delete the file after processing
#  rotate     - keep approximately C<$rotatesize> bytes of the file after
#               processing
#  keep       - leave the log file after processing.
# The 'force' key is a boolean.
sub pre_process_logs {
    my $procdesc   = shift;
    my $logs_ref   = shift;
    my $homedir    = shift;
    my $uid        = shift;
    my $gid        = shift;
    my $rotatesize = shift // 1024 * 1024 * 1024;
    my ( $postprocess, $force ) = @{$procdesc}{ 'type', 'force' };

    return 0 if 'keep' eq $postprocess;

    my $ret = 0;

    # can be refactored into a hash based dispatch
    if ( 'delete' eq $postprocess ) {

        # perform logfile backup
        $ret = _preprocess_delete($logs_ref);
    }
    elsif ( 'rotate' eq $postprocess ) {
        $ret = _preprocess_rotate( $logs_ref, $rotatesize, $NO_ARCHIVE );
    }
    elsif ( 'sysarchive' eq $postprocess ) {
        if ($force) {
            $ret = _preprocess_sysarchive_delete($logs_ref);
        }
        else {
            $ret = _preprocess_sysarchive_rotate( $logs_ref, $rotatesize, $DO_ARCHIVE );
        }
    }
    elsif ( 'userarchive' eq $postprocess ) {
        if ($force) {
            $ret = _preprocess_delete($logs_ref);
        }
        else {
            $ret = _preprocess_rotate( $logs_ref, $rotatesize, $DO_ARCHIVE );
        }
    }

    # create symlinks in $homedir for user to see contents of log that is currently being processed;
    # symlink is removed in Cpanel::Logs::post_process_logs (below); only create if $homedir, $uid, and $gid are provided
  CREATE_HOME_SYMLINK:
    if ( defined $homedir and defined $uid and defined $gid ) {
        my $logdir = qq{$homedir/logs};
        local $@;

        # Its possible that the home directory is missing and this will fail.
        # In that case we want to warn and move on.  If we die here it will
        # cause all log pre-processing to fail since this function is called
        # in a loop for all users that we need to process.
        eval { create_user_home_symlinks( $logs_ref, $logdir, $uid, $gid ); };
        warn if $@;
    }

    return $ret;
}

sub create_user_home_symlinks {
    my ( $logs_ref, $logdir, $uid, $gid ) = @_;
    my $logger = Cpanel::Logger->new();

    my $create_link_coderef = sub {

        # If $logdir is relative, you NEED to assume we're referring to the
        # user's homedir, as otherwise the system will assume it is root.
        # Issue was exposed by adding warning checks to t/Cpanel-Logs_log_processing.t
        my $home = $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);
        $logdir = $home . '/' . $logdir if index( $logdir, '/' ) != 0;

        # ensure $logdir exists, if not create and set proper owner
        if ( not -d $logdir ) {

            # move $logdir out of the way if it not a directory, this case is covered by prep_logs_path
            if ( -e $logdir ) {
                rename $logdir, qq{$logdir.$$} or die qq{Rename failed when moving regular file $logdir out of the way to make room for a directory of the same name: $!};
            }

            # Sometimes, the path component path to the dir doesn't exist.
            # As such we'll have to use Cpanel::Mkdir instead.
            # This of course, does not come without *risk*, as in the test which
            # exposes this, the directory referred to was tmp/logs.
            # $HOME/tmp of course is normally 0755 on cPanel systems, so any
            # code which manages that directory would have to become paranoid
            # about permissions in that case, much less the permssions on
            # the homedir components up to there if they don't exist, though
            # for the homedir, you likely already have "bigger problems" if
            # those path components do not exist.
            Cpanel::Mkdir::ensure_directory_existence_and_mode( $logdir, 0700 ) or die qq{Can't create $logdir: $!};
            $logger->info(qq{Created $logdir because it doesn't exist.});
        }

      CREATE_SYMLINK:
        foreach my $log_ref (@$logs_ref) {
            next CREATE_SYMLINK if not $log_ref->{'logfile'} or not -e $log_ref->{'logfile'};
            my $file     = $log_ref->{'logfile'};
            my $basename = File::Basename::basename($file);

            my $symlink = qq{$logdir/$basename};

            # checks to make sure $symlink doesn't exist in any form (-e is true for any link or file)
            symlink $file, $symlink if not -e $symlink;
        }
    };

    Cpanel::AccessIds::ReducedPrivileges::call_as_user( $create_link_coderef, $uid );

    return 1;
}

sub remove_user_home_symlinks {
    my ( $logs_ref, $logdir, $user ) = @_;

    my $remove_link_coderef = sub {
      REMOVE_SYMLINK:
        foreach my $log_ref (@$logs_ref) {
            next REMOVE_SYMLINK if not $log_ref->{'logfile'};
            my $file     = $log_ref->{'logfile'};
            my $basename = File::Basename::basename($file);
            my $symlink  = qq{$logdir/$basename};

            # checks to make sure $symlink exists and is actually a link (-l)
            unlink $symlink if -l $symlink;
        }
    };

    Cpanel::AccessIds::ReducedPrivileges::call_as_user( $remove_link_coderef, $user );

    return 1;
}

#
# Handles the cases where we want to keep the file (mostly) intact, but not let
# grow too much larger than C<$rotatesize>.
# C<$logs_ref> is an arrayref containing logfile descriptions
sub _preprocess_rotate {
    my ( $logs_ref, $rotatesize, $archive ) = @_;
    my $count  = 0;
    my $logger = Cpanel::Logger->new();

    foreach my $logdesc ( @{$logs_ref} ) {

        # split file
        my $file = $logdesc->{logfile};

        # First clean out 0-length files (that should not be there) and then process
        clean_debris($file);
        my $bkup = backup_filename($file);
        if ( -e $bkup ) {
            $logger->info("Backup file '$bkup' found, completing interrupted processing.\n");
            $logdesc->{logfile} = $bkup;
        }
        elsif ( -s $file <= $rotatesize ) {
            $logdesc->{keep} = 1;
        }
        elsif ( eval { rotate_file( $file, $bkup, $rotatesize, $archive ) } ) {
            $logdesc->{logfile} = $bkup;
            ++$count;
        }
        else {
            $logdesc->{keep} = 1;
            $logger->warn("Unable to rotate '$file': $!\n");
        }
    }
    return $count;
}

#
# Handles the cases where we want to keep the file (mostly) intact, but not let
# grow too much larger than C<$rotatesize>.
# Includes special cases for trunctate-only logfiles
# C<$logs_ref> is an arrayref containing logfile descriptions
sub _preprocess_sysarchive_rotate {
    my ( $logs_ref, $rotatesize ) = @_;
    my $count  = 0;
    my $logger = Cpanel::Logger->new();
    foreach my $logdesc ( @{$logs_ref} ) {

        # split file
        my $file = $logdesc->{logfile};

        # First clean out 0-length files (that should not be there) and then process
        clean_debris($file);
        my $bkup = backup_filename($file);
        if ( -e $bkup ) {
            $logger->info("Backup file '$bkup' found, completing interrupted processing.\n");
            $logdesc->{logfile} = $bkup;
        }
        elsif ( -s $file < $rotatesize ) {
            $logdesc->{keep} = 1;
        }
        elsif ( _logfile_is_truncate_only($file) ) {
            $logdesc->{truncate} = 1;
            ++$count;
        }
        elsif ( rename( $file, $bkup ) ) {
            $logdesc->{logfile} = $bkup;
            ++$count;
            rename( "$file.offset", "$bkup.offset" ) if -e "$file.offset";
        }
        else {
            $logdesc->{keep} = 1;
            $logger->warn("Unable to rotate '$file': $!\n");
        }
    }
    return $count;
}

#
# Handles the cases where we want to process and delete the file.
# Includes special cases for trunctate-only logfiles
# C<$logs_ref> is an arrayref containing logfile descriptions
sub _preprocess_sysarchive_delete {
    my ($logs_ref) = @_;
    my $count      = 0;
    my $logger     = Cpanel::Logger->new();
    foreach my $logdesc ( @{$logs_ref} ) {
        my $file = $logdesc->{logfile};

        # First clean out 0-length files (that should not be there) and then process
        clean_debris($file);
        my $bkup = backup_filename($file);
        if ( -e $bkup ) {
            $logger->info("Backup file '$bkup' found, completing interrupted processing.\n");
            $logdesc->{logfile} = $bkup;
        }
        elsif ( _logfile_is_truncate_only($file) ) {
            $logdesc->{truncate} = 1;
            ++$count;
        }
        elsif ( rename( $file, $bkup ) ) {
            $logdesc->{logfile} = $bkup;
            ++$count;
            rename( "$file.offset", "$bkup.offset" ) if -e "$file.offset";
        }
        else {
            $logdesc->{keep} = 1;
            $logger->warn("Unable to rename '$file' to '$bkup': $!\n");
        }
    }
    return $count;
}

#
# Handles the cases where we want to process and delete the file.
# C<$logs_ref> is an arrayref containing logfile descriptions
sub _preprocess_delete {
    my ($logs_ref) = @_;
    my $count      = 0;
    my $logger     = Cpanel::Logger->new();
    foreach my $logdesc ( @{$logs_ref} ) {
        my $file = $logdesc->{logfile};

        # First clean out 0-length files (that should not be there) and then process
        clean_debris($file);
        my $bkup = backup_filename($file);
        if ( -e $bkup ) {
            $logger->info("Backup file '$bkup' found, completing interrupted processing.\n");
            $logdesc->{logfile} = $bkup;
        }
        elsif ( eval { rotate_file( $file, $bkup, 0, 1 ) } ) {
            $logdesc->{logfile} = $bkup;
            ++$count;
        }
        else {
            $logdesc->{keep} = 1;
            $logger->warn("Unable to rename '$file' to '$bkup': $!\n");
        }
    }
    return $count;
}

# Decide whether the supplied logfile should be truncated in place or rotated+unlinked
sub _logfile_is_truncate_only {
    my $filepath = shift;

    # PHP-FPM logfiles are always archived/truncated in place
    return 1 if ( index( $filepath, '/var/cpanel/php-fpm/' ) == 0 );

    # Other sysarchive logfiles are archives/truncated in place if they have the append-only flag
    if ( open my $fh, '<', $filepath ) {
        return Cpanel::Sys::Chattr::get_attribute( $fh, 'APPEND' ) ? 1 : 0;
    }

    return 0;
}

sub check_pre_process_state {
    my ( $postprocess, $logs_ref ) = @_;
    return 0 if 'keep' eq $postprocess;
    my $count = 0;
    foreach my $logdesc ( @{$logs_ref} ) {
        my $file = $logdesc->{logfile};
        my $bkup = backup_filename($file);
        if ( -e $bkup ) {
            $logdesc->{logfile} = $bkup;
            ++$count;
        }
        else {
            $logdesc->{keep} = 1;
        }
    }
    return $count;
}

#
# If the supplied C<$path> does not exist, create it. Also make certain the file
# F<README.archive> exists in that directory.
sub prep_archive_path {
    my ($path) = @_;

    # or mode of parent dir or default of function ?
    Cpanel::SafeDir::MK::safemkdir( $path, '0700' ) unless -d $path;

    return if -e "$path/README.archive";
    if ( open my $rm_fh, '>', "$path/README.archive" ) {
        print {$rm_fh} <<'END_README';
Any archived files in this directory are named after the date they were rotated.

Hence, the file names *do not relate* in any way to the content of the file being rotated.

Also, they are only created when the file needs rotated. That means that there will often be gaps in the date sequence of the names for files.

END_README
        close $rm_fh;
    }
    return;
}

#
# If the supplied C<$path> does not exist, create it.
sub prep_logs_path {
    my ( $path, $user ) = @_;

    if ( !-d $path ) {
        my ( $uid, $gid ) = ( Cpanel::PwCache::getpwnam($user) )[ 2, 3 ];
        my $as_user_cr = sub {
            my $msgs = [];
            if ( -e $path && !-d $path ) {
                push @$msgs, "$path exists but is not a directory. Changing its name to $path.$$";
                rename $path, "$path.$$" or push @$msgs, "Rename failed: $!";
            }
            if ( !-d $path ) {

                # at this point we've already tried to ensure its either non existant or a directory
                mkdir( $path, 0700 ) || push @$msgs, "Could not mkdir $path: $!";
            }
            return $msgs;
            ## no critic(ProhibitUnreachableCode)
        };
        my $logger = Cpanel::Logger->new();
        my $msgs;

        if ($>) {
            $msgs = $as_user_cr->();
        }
        else {
            $msgs = Cpanel::AccessIds::ReducedPrivileges::call_as_user( $as_user_cr, $uid, $gid );
        }
        $logger->warn($_) foreach @$msgs;
    }

    if ( !-d $path ) {
        print "Skipping $path because it not a directory and attempts to rectify it failed as per the errors above.\n";
        return 1;
    }
    return;
}

#
# Perform whatever post-processing is needed based on the C<$type> argument,
# on the files described by the C<$logs_ref> array of hashes.
#
# Return the number of files modified. Exception on failures.
#
# C<$type> can contain one of the following values:
#  sysarchive  - compress the data in the file and delete when finished
#  userarchive - compress the data in the file and delete when finished
#  delete      - delete the file after processing
#  rotate      - keep approximately C<$rotatesize> bytes of the file after processing
#  keep        - leave the log file after processing.
#
# The final argument C<$args> contains some context information about the
# system used by the I<userarchive> processing type.
#
#  archivedir - The directory where archives are stored
#  user       - The user name that owns the logs
sub post_process_logs {
    my ( $type, $logs_ref, $args ) = @_;
    $args = {} unless defined $args;

    return 0 if 'keep' eq $type;

    if ( $args->{user} && $args->{archivedir} ) {
        remove_user_home_symlinks( $logs_ref, $args->{archivedir}, $args->{user} );
    }

    my $logger = Cpanel::Logger->new();
    my $count  = 0;

    # elsif can be rewritten as a hash based dispatch table
    if ( 'sysarchive' eq $type ) {
        my ( $m, $y ) = (localtime)[ 4, 5 ];
        foreach my $logdesc ( @{$logs_ref} ) {
            next if exists $logdesc->{keep} && $logdesc->{keep};
            my $file = $logdesc->{logfile};
            my ( $path, $orig ) = ( $file =~ m{^(.*)/([^/]+)$} );
            $orig =~ s/\.bkup$//;
            $path .= '/archive';
            prep_archive_path($path);
            my $suffix  = _get_archive_suffix($file);
            my $archive = sprintf "$path/$orig-%02d-%04d%s.gz", $m + 1, $y + 1900, $suffix;

            if ( eval { archive_file( $file, $archive ) } ) {
                ++$count;

                #We can’t remove the file because in some cases
                #(e.g., cPanel-PHP-FPM) the filesystem permissions only
                #permit writing to an existing file, not creating a new one.
                if ( $logdesc->{truncate} ) {
                    Cpanel::Logs::Truncate::truncate_logfile($file) or $logger->warn("Failed to empty archived backup “$file”: $!\n");
                }
                else {
                    unlink($file) or $logger->warn("Unable to remove archived backup '$file:' $!\n");
                }

                unlink("$file.offset");
            }
            else {
                $logger->warn("Unable to archive '$file': $@: $!\n");
            }
        }
    }
    elsif ( 'userarchive' eq $type ) {
        my ( $m, $y ) = (localtime)[ 4, 5 ];
        my $failed = prep_logs_path( @{$args}{qw/archivedir user/} );
        if ( not $failed ) {    # deferred return until later, $count still 0 if $failed
            my $archivedir = $args->{archivedir};
            foreach my $logdesc ( @{$logs_ref} ) {
                next if exists $logdesc->{keep} && $logdesc->{keep};
                my $file = $logdesc->{logfile};
                my ($orig) = ( $file =~ m{/([^/]+?)(?:\.bkup)?$}g );

                my $suffix  = _get_archive_suffix($file);
                my $archive = sprintf "$archivedir/$orig-%s-%04d%s.gz", $MonthName[$m], $y + 1900, $suffix;
                if ( eval { archive_file( $file, $archive, $args->{user} ) } ) {
                    ++$count;
                    unlink($file) or $logger->warn("Unable to remove archived backup '$file': $!\n");
                    unlink("$file.offset");
                }
                else {
                    $logger->warn("Unable to archive '$file': $@: $!\n");
                }
            }
        }
    }
    elsif ( 'delete' eq $type || 'rotate' eq $type ) {
        foreach my $logdesc ( @{$logs_ref} ) {
            next if exists $logdesc->{keep} && $logdesc->{keep};

            my $file = $logdesc->{logfile};
            if ( unlink($file) ) {
                ++$count;
                unlink("$file.offset");
            }
            else {
                $logger->warn("Unable to delete '$file': $!\n");
            }
        }
    }

    return $count;
}

#
# Find the previous month and year (1-based month and real year) from the supplied
# day, month, and year (from localtime). Previous month is determined either one or
# two months back depending on whether we are in the first or second half of the
# month.
sub previous_month_and_year {
    my ( $d, $m, $y ) = @_;

    --$m if $d < 14;
    if ( $m < 1 ) {
        $m += 11;
        --$y;
    }
    else {
        --$m;
    }
    return ( $m + 1, $y + 1900 );
}

#
# Remove last month's archive file for
sub remove_old_user_archives {
    my ( $archivedir, $logs ) = @_;
    my ( $m,          $y )    = previous_month_and_year( (localtime)[ 3, 4, 5 ] );
    my $logger = Cpanel::Logger->new();

    foreach my $logdesc ( @{$logs} ) {
        next if exists $logdesc->{keep} && $logdesc->{keep};
        my $file = $logdesc->{logfile};
        my ($prefix) = ( $file =~ m{([^/]+)$}g );
        $prefix =~ s/\.bkup$//;

        my $suffix = _get_archive_suffix($file);
        my $gzfile = sprintf "$prefix-%s-%04d%s.gz", $MonthName[ $m - 1 ], $y, $suffix;

        my $archive = "$archivedir/$gzfile";
        if ( -e $archive ) {
            print "Unlinking old log archive ($gzfile)\n";
            unlink $archive or $logger->warn("Could not unlink $archive: $!");
        }
    }
    return;
}

sub _get_archive_suffix {
    my ($path) = @_;
    return path_is_nginx_domain_log($path) ? "_NGINX" : "";
}

sub path_is_nginx_domain_log {
    my ($path) = @_;
    return if !length($path);

    my $dir_slash = Cpanel::EA4::Constants::nginx_domain_logs_dir . "/";
    return index( $path, $dir_slash ) == 0 && length($path) > length($dir_slash) ? 1 : 0;
}

1;
