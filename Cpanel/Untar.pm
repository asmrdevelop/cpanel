
# cpanel - Cpanel/Untar.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Untar;

use strict;
use warnings;

use Cpanel::Autodie       ();
use Cpanel::Exception     ();
use Cpanel::PwCache       ();
use IO::Uncompress::Untar ();

use Cpanel::Imports;

use constant _ENOENT => 2;
use constant _EACCES => 13;

=head1 MODULE

C<Cpanel::Untar>

=head1 DESCRIPTION

C<Cpanel::Untar> provides a perl replacement for /bin/tar
with any of the following options:

=over

=item --xvfz (for .tar.gz)

=item --xvfj (for .tar.bz2)

=item --xvf  (for .tar)

=back

=head2 CAUTION

When run as root, this module can restore files, permission and ownership to any
file below the destination directory or if the destination directory is not provided
to the current working directory.

Be cautious when restoring files as root since you can overwrite important system files
or install unsafe symbolic links and probably many other risky things.

head2 NOTE

This module can only restore the following file system types. All other entries stored
in the archive will either result in a progress log entry about being unsupported or will
be ignored depending on the options you pass.

=head2 Monitoring Progress

The module has an extension system that lets you send serialized progress events to a file handle
passed in the notice_fh. You can control the formatting of the messages by providing a callback
in the notices_formatter with the following signature:

  sub format {
    my ( $type, $name, $data ) = @_;
    ...
    return $formatted_message;
  }

=head3 CALLBACK ARGUMENTS

=over

=item C<$type> - string

Unique type: 'error' or 'success'

=item C<$name> - string

Name of the event.

=item C<$data> - hashref

Data associated with the event. If you want to include it, you need to serialize it to the output format.

=back

=head3 CALLBACK RETURNS

Data that will be written directly to the notice_fh. Commonly this is a string, but that
is not a hard requirement.

=over

=item FILE

=item HARDLINK

=item SYMLINK

=item DIR

=back

=head1 SYNOPSIS

  use Cpanel::Untar;
  mkdir '/tmp/restore';

  # Restore the archive to the current directory
  Cpanel::Untar('/tmp/archive.tar.gz');

  # Restore the archive to a specific directory
  Cpanel::Untar('/tmp/archive.tar.gz', '/tmp/restore/');

  # Restore the archive to a specific directory, removing stored parent directory
  #  In the archive files are stored as ./restore/...
  Cpanel::Untar('/tmp/archive.tar.gz', '/tmp/restore/', truncate_path => 'restore/');

=cut

use constant FILE     => 0;
use constant HARDLINK => 1;
use constant SYMLINK  => 2;
use constant CHARDEV  => 3;
use constant BLOCKDEV => 4;
use constant DIR      => 5;
use constant FIFO     => 6;
use constant SOCKET   => 8;
use constant UNKNOWN  => 9;
use constant LONGLINK => 'L';

=head1 FUNCTIONS

=head2 untar_to_directory(ARCHIVE, DIRECTORY, OPTS)

Untar the archive to the specified directory.

=head3 ARGUMENTS

=over

=item ARCHIVE - string

Path to the archive file.

=item DIRECTORY - string

Path where you want the archive to be expanded to.

=item OPTS - hash

=over

=item truncate_path - string

Path prefix to remove from relative paths in the archive.

=item ignore_unsupported - Boolean

Do not die if unsupported file types are included in the archive.

=item user - string

Default user who should own the files.

=item notice_fh - Filehandle

Optional. If present, messages about the untar are written to this.

=item notice_formatter - CODE Reference

Optional. If present, and notice_fh is also present, message will be written using
this custom formatter.

=item verbose - Boolean

If true, more output will be printed to the notice_fh.

=back

=back

=head3 THROWS

=over

=item When the provided ARCHIVE is not an archive, or it is empty.

=item When the ARCHIVE or DIRECTORY parameter are missing.

=item When the ARCHIVE parameter is an empty string.

=item When the ARCHIVE parameter is not a file on the file system.

=item When the DIRECTORY parameter is not a directory on the file system.

=item When the notice_fh is provided, but is not a file handle.

=item When the notice_formatter is provided, but not a callable subroutine.

=item When the archive can not be opened by IO::Uncompress::Untar.

=item When the LONGLINK name stream is empty.

=item When the LONGLINK name stream doesn't contain a valid name.

=back

=cut

sub untar_to_directory {
    my ( $archive, $directory, %opts ) = @_;
    _validate_archive_param($archive);
    _validate_directory_param($directory);

    my $output_dir = _initialize_output_directory($directory);
    my ( $verbose, $truncate_path, $ignore_unsupported, $user ) = _initialize_core_options(%opts);
    my ( $notice_fh, $notice_formatter )                        = _inititialze_progress_notice_adapter(%opts);
    my ( undef, undef, $uid, $gid )                             = Cpanel::PwCache::getpwnam($user);

    my $untar = _open_tarfile( $archive, %opts );
    my $real_name;
    my $file_count = 0;

    while ( ( my $status = $untar->nextStream() ) != 0 ) {
        $file_count++;

        if ( $status == -1 ) {
            _error( $notice_fh, &$notice_formatter( 'error', 'untar_failed', { description => $IO::Uncompress::Untar::UntarError, archive => $archive } ) );
            last;
        }

        my $header    = $untar->getHeaderInfo();
        my $filename  = $header->{name};
        my $file_type = $header->{typeflag};

        if ( $file_type eq LONGLINK ) {

            my $buffer = undef;
            $untar->read($buffer);

            die( Cpanel::Exception->create_raw( locale()->maketext("The system failed to read from the data stream.") ) ) if ( !$buffer );
            $real_name = substr( $buffer, 0, $header->{size} - 1 );
            die( Cpanel::Exception->create_raw( locale()->maketext("The system failed to retrieve a valid path from the stream.") ) ) if ( !$real_name );

            next;

        }
        else {
            if ($real_name) {
                $filename  = $real_name;
                $real_name = undef;
            }
        }

        last if ( !defined $filename );
        $filename = _adjust_archive_relative_path_to_output_relative_path( $filename, $truncate_path );

        my $full_path = $output_dir . $filename;
        my $created   = 0;

        eval {
            if ( $file_type == FILE ) {
                _create_file( $untar, $full_path );
                $created = 1;
            }
            elsif ( $file_type == DIR ) {
                Cpanel::Autodie::mkdir_if_not_exists($full_path);
                $created = 1;
            }
            elsif ( $file_type == HARDLINK ) {
                _create_link( $header->{linkname}, $full_path, $truncate_path, $output_dir );
                $created = 1;
            }
            elsif ( $file_type == SYMLINK ) {
                _create_symlink( $header->{linkname}, $full_path, $truncate_path, $output_dir );
                $created = 1;
            }
            elsif ( $file_type == CHARDEV && !$ignore_unsupported ) {
                die Cpanel::Exception::create( 'Unsupported', 'Character devices are not supported.' );
            }
            elsif ( $file_type == BLOCKDEV && !$ignore_unsupported ) {
                die Cpanel::Exception::create( 'Unsupported', 'Block devices are not supported.' );
            }
            elsif ( $file_type == FIFO && !$ignore_unsupported ) {
                die Cpanel::Exception::create( 'Unsupported', 'FIFOs are not supported.' );
            }
            elsif ( $file_type == SOCKET && !$ignore_unsupported ) {
                die Cpanel::Exception::create( 'Unsupported', 'Sockets are not supported.' );
            }
            elsif ( !$ignore_unsupported ) {
                die Cpanel::Exception::create( 'Unsupported', 'Unrecognized types are not supported.' );
            }

            if ($created) {

                # leave the default permission since on linux permissions
                # are checked on the file at the other end of the link.
                if ( $file_type != SYMLINK ) {
                    Cpanel::Autodie::chmod( $header->{mode}, $full_path );
                }

                if ( $> == 0 ) {
                    _chown( $uid, $gid, $header, $user, $full_path );
                }

                if ( $file_type != SYMLINK ) {

                    # Note: Symlinks do not support mtime really. Modifying
                    # the mtime using utime would change the mtime of the
                    # file or directory at the other end of the symlink.
                    _utime( $header->{mtime}, $header->{mtime}, $full_path )
                      or die Cpanel::Exception->create( 'The system failed to set the access time or the modify time for “[_1]”.', [$full_path] );
                }

            }
        };

        if ( my $exception = $@ ) {
            _error( $notice_fh, &$notice_formatter( 'error', 'untar_failed', { archive => $archive, header => $header, description => $exception } ) );
        }
        else {
            if ($verbose) {
                _write( $notice_fh, &$notice_formatter( 'debug', 'untar_success', { archive => $archive, header => $header, description => $header->{name} } ) );
            }
        }
    }
    if ( $file_count == 0 ) { die Cpanel::Exception->create('Failed to restore files to the home directory. The provided file is not an archive, or the archive is empty.') }

    return;
}

=head2 _validate_archive_param(ARCHIVE) [PRIVATE]

Validate the archive is something we can use.

=cut

sub _validate_archive_param {
    my $archive = shift;
    die Cpanel::Exception::create( 'MissingParameter', ['archive'] ) if !defined $archive;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter for is empty.',                               ['archive'] ) if $archive eq '';
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” path provided in the “[_2]” parameter is not a file.',  [ $archive, 'archive' ] ) if !-f $archive;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” path provided in the “[_2]” parameter cannot be read.', [ $archive, 'archive' ] ) if !-r $archive;
    return;
}

=head2 _validate_directory_param(DIRECTORY) [PRIVATE]

Validate the directory is something we can use.

=cut

sub _validate_directory_param {
    my $directory = shift;
    die Cpanel::Exception::create( 'MissingParameter', ['directory'] ) if !$directory;
    die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” path provided in the “[_2]” parameter is not a directory.', [ $directory, 'directory' ] ) if !-d $directory;
    return;
}

=head2 _open_tarfile(ARCHIVE, OPTIONS) [PRIVATE]

Open the request tar archive with the provided options.

=head3 THROWS

When the archive can not be opened by IO::Uncompress::Untar.

=cut

sub _open_tarfile {
    my ( $archive, %opts ) = @_;
    my $untar = eval { IO::Uncompress::Untar->new( $archive, %opts ) };
    if ( !$untar || $@ ) {
        if ( $! == _ENOENT ) {
            die Cpanel::Exception->create(
                'The “[_1]” path does not exist.',
                [$archive]
            );
        }
        elsif ( $! == _EACCES ) {
            die Cpanel::Exception->create(
                'The “[_1]” path cannot be read.',
                [$archive]
            );
        }
        elsif ($@) {
            die Cpanel::Exception->create_raw($@);
        }
        else {
            die Cpanel::Exception->create(
                'Failed to open “[_1]” with the error: [_2]',
                [ $archive, $IO::Uncompress::Untar::UntarError ]
            );
        }
    }

    return $untar;
}

=head2 _initialize_output_directory(DIR) [PRIVATE]

Calculate the output directory.

=cut

sub _initialize_output_directory {
    my $directory  = shift;
    my $output_dir = $directory || do { require Cwd; Cwd::getcwd(); };
    $output_dir .= '/' if $output_dir !~ m{/$};
    return $output_dir;
}

=head2 _initialize_core_options(OPTS) [PRIVATE]

Setup the core options for the process from the OPTS and defaults.

=cut

sub _initialize_core_options {
    my %opts               = @_;
    my $verbose            = $opts{verbose}            // 0;
    my $truncate_path      = $opts{truncate_path}      // '';
    my $ignore_unsupported = $opts{ignore_unsupported} // 0;
    my $user               = $opts{user}               // $Cpanel::user // ( Cpanel::PwCache::getpwuid($>) )[0];
    return ( $verbose, $truncate_path, $ignore_unsupported, $user );
}

=head2 _inititialze_notice_adapter(OPTS) [PRIVATE]

Setup the progress event notification system. If one is not provided in the options,
then the default one is used.

=cut

sub _inititialze_progress_notice_adapter {
    my %opts = @_;
    my $fh   = $opts{notice_fh} // undef;
    if ( $fh && ref $fh ne 'GLOB' ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” option must be a valid file handle.", ['notice_fh'] );
    }

    my $formatter = $opts{notice_formatter} // \&_format_notice;
    if ( $formatter && ref $formatter ne 'CODE' ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” option must be a code reference.", ['notice_formatter'] );
    }
    return ( $fh, $formatter );
}

=head2 _adjust_archive_relative_path_to_output_relative_path(PATH, TRUNCATE) [PRIVATE]

Adjust the stored path name to be suitable for placing the file in a specific location on disk.

Note, if TRUNCATE is passed, the part of the path defined by ./TRUNCATE will be removed. This is
used to adjust paths in some archive that include extra directories at the root.

=cut

sub _adjust_archive_relative_path_to_output_relative_path {
    my ( $filename, $truncate_path ) = @_;
    if ($truncate_path) {
        $filename =~ s{^./\Q$truncate_path\E}{};
    }
    else {
        $filename =~ s{^./}{};
    }
    return $filename;
}

=head2 _chown(UID, GID, HEADER, USER, FULL_PATH) [PRIVATE]

Change ownership to what the archive specifies.

=cut

sub _chown {
    my ( $uid, $gid, $header, $user, $full_path ) = @_;

    my ( $luid, $lgid ) = ( $uid, $gid );

    # Only root can adjust the ownership to someone other than current user.
    if ( $header->{uname} && $header->{uname} ne $user ) {
        ( undef, undef, $luid ) = Cpanel::PwCache::getpwnam( $header->{uname} );
    }
    if ( $header->{gname} && $header->{gname} ne $user ) {
        ( undef, undef, undef, $lgid ) = Cpanel::PwCache::getpwnam( $header->{gname} );
    }
    Cpanel::Autodie::chown( $luid, $lgid, $full_path );
    return;
}

=head2 _create_file(UNTAR, FULL_PATH)

Create a file from the information in the untar stream.

=cut

sub _create_file {
    my ( $untar, $full_path ) = @_;

    # Ensure we have write permissions on the file
    Cpanel::Autodie::chmod( 0600, $full_path ) if -e $full_path;

    Cpanel::Autodie::open( my $fh, '>', $full_path );
    binmode($fh);

    my $buffer = undef;
    while ( ( my $status = $untar->read( $buffer, 1024 ) ) > 0 ) {
        print {$fh} $buffer;
    }

    Cpanel::Autodie::close($fh);
    return;
}

=head2 _create_link(LINK_PATH, FULL_PATH, TRUNCATE_PATH, OUTPUT_DIR)

Create a hard link based on the passed in rules.

=cut

sub _create_link {
    my ( $link_path, $full_path, $truncate_path, $output_dir ) = @_;
    $link_path = _adjust_link_path( $link_path, $truncate_path, $output_dir );
    Cpanel::Autodie::link_if_no_conflict( $link_path, $full_path );
    return;
}

=head2 _create_symlink(LINK_PAHT, FULL_PATH, TRUNCATE_PATH, OUTPUT_DIR)

Create a symbolic link based on the passed in rules.

=cut

sub _create_symlink {
    my ( $link_path, $full_path, $truncate_path, $output_dir ) = @_;
    $link_path = _adjust_link_path( $link_path, $truncate_path, $output_dir );
    Cpanel::Autodie::symlink_if_no_conflict( $link_path, $full_path );
    return;
}

=head2 _adjust_link_path(LINK, TRUNCATE, OUTPUT)

Change relative paths to a specific path.

=cut

sub _adjust_link_path {
    my ( $link_path, $truncate_path, $output_dir ) = @_;
    if ($output_dir) {
        $output_dir = $output_dir . ( $output_dir =~ m{/$} ? '' : '/' );
    }

    if ( $link_path =~ m{^./} ) {    # is relative
        if ($truncate_path) {
            $link_path =~ s{^./\Q$truncate_path\E/}{$output_dir};
        }
        else {
            $link_path =~ s{^./}{$output_dir};
        }
    }
    return $link_path;
}

=head2 _error(FH, MESSAGE) [PRIVATE]

Write an error message.

=cut

sub _error {
    my ( $fh, $message ) = @_;
    if ($fh) {
        print {$fh} $message;
    }
    else {
        logger()->warn($message);
    }
    return;
}

=head2 _write(FH, MESSAGE) [PRIVATE]

Write a message.

=cut

sub _write {
    my ( $fh, $message ) = @_;
    if ($fh) {
        print {$fh} $message;
    }
    else {
        logger()->info($message);
    }
    return;
}

=head2 _format_notice(TYPE, NAME, DATA)

Default message formatter if not custom notice_formatter is provided in the parameters.

=head3 RETURNS

string - formatted message.

=cut

sub _format_notice {
    my ( $type, $name, $data ) = @_;
    if ( $type eq 'error' && $name eq 'untar_failed' ) {
        if ( $data->{header} ) {
            return "ERROR: " . $data->{header}{name} . " - " . $data->{description} . "\n";
        }
        else {
            return "ERROR: " . $data->{description} . "\n";
        }
    }
    elsif ( $type eq 'success' && $name eq 'untar_done' ) {
        return $data->{header}{name} . "\n";
    }
    else {
        return "Unrecognized event: $type, $name\n";
    }
}

# for testing
sub _utime {
    return utime( $_[0], $_[1], $_[2] );
}
1;
