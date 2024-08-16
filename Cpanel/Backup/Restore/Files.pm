package Cpanel::Backup::Restore::Files;

# cpanel - Cpanel/Backup/Restore/Files.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Backup::Restore::Base);

use Cpanel::Background::Log::FrameFormatter ();
use Cpanel::Exception                       ();
use Cpanel::Mkdir                           ();
use Cpanel::Path::Homedir                   ();
use Cpanel::PipeHandler                     ();
use Cpanel::Security::Authz                 ();
use Cpanel::Untar                           ();
use Cpanel::Upload                          ();
use IO::Select                              ();

use Cpanel::Imports;

use Errno qw[EINTR];

use constant {
    RESTORE_FILES_TIMEOUT => 7200,    # 2 hours in seconds
};

=head1 MODULE

C<Cpanel::Backup::Restore::Files>

=head1 DESCRIPTION

C<Cpanel::Backup::Restore::Files> provides a mechanism to restore a
set of file system backups.

=head1 SYNOPSIS

  use Cpanel::Backup::Restore::Files;
  my $restore = Cpanel::Backup::Restore::Files->new();

  # Restore a backup to the home directory.
  $restore->restore([
    '/home/cpuser/backups/domain.tar.gz'
  ]);

  # Restore a backup to a specific directory.
  $restore->restore([
    '/home/cpuser/backups/domain.tar.gz'
  ], directory => '/home/cpuser/restore');


=head1 CONSTRUCTOR

=head2 Cpanel::Backup::Restore::Files->new(dir => ..., timeout => ...)

Create a new instance of C<Cpanel::Backup::Restore::Files>

=head3 ARGUMENTS

=over

=item directory - string

Directory to restore to. Defaults to the users home directory.

=item timeout - number

Number of seconds until the restore times out. Defaults to 2 hours.

=back

=head3 RETURNS

C<Cpanel::Backup::Restore::Files>

=cut

sub new {
    my ( $class, %options ) = @_;
    $options{timeout} //= RESTORE_FILES_TIMEOUT;
    $options{type} = 'restorefiles';
    my $self = $class->SUPER::new(%options);
    return $self;
}

=head1 METHODS

=head2 INSTANCE->restore(FILES, OPTIONS)

Restores the list of archives to the specified location. The location will
be the users homedir unless otherwise specified in the OPTIONS or in the
constructor options.

=head3 ARGUMENTS

=over

=item FILES - arraryref of strings

Optional. Each string is a path to a file system archive containing directories
and files to restore to the specified location. Only the following types
of filesystem objects in the archives will be restored:

=over

=item * file

=item * directory

=item * hardlink

=item * softlink

=back

The archives will be restored in the order passed in. The ownership and permissions
of the files will be restored to what is indicated within the archive if allowed by
in the context of the current user.

B<Note:> It this is not provided, then it is assumed that the files were uploaded to
the server instead. The backup files will be collected from the FORM upload system
in this case.

=item OPTIONS - hash

With the following options:

=over

=item directory - string

Directory to extract the archives to. If not provided this will default to
what is provided in the constructor. If not provided in either the option or the constructor,
the users home directory will be the destination.

=back

=back

=head3 RETURNS

Cpanel::Background::Log instance with the complete list of events processed during the restore.

=cut

sub restore {
    my ( $self, $files, %options ) = @_;
    Cpanel::Security::Authz::verify_not_root();

    my $directory = $options{directory} // $self->{directory} // Cpanel::Path::Homedir::get_homedir();

    $directory = $self->normalize_path($directory);
    $files     = $self->normalize_paths($files);
    $self->validate_files_parameter($files);

    if ( !-d $directory ) {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $directory, 0700 );
        $self->log->info( 'create_directory', { description => locale()->maketext( 'Created the “[_1]” restore directory.', $directory ) } );
    }

    my $alarm = $self->create_alarm(
        'files',
        locale()->maketext('The system failed to restore the file system due to a timeout.')
    );

    local $SIG{PIPE} = \&Cpanel::PipeHandler::pipeBGMgr;

    Cpanel::Upload::process_files(
        sub {
            $self->restore_one_callback(@_);
        },
        $files,
        {
            log       => $self->log(),
            directory => $directory,
        }
    );

    $self->log()->close();

    return $self->log();
}

=head2 INSTANCE->restore_one_callback(file => ..., temp_file => ..., args => ...)

Method that restores a single archive to the destination directory.

=head3 ARGUMENTS

Hash with the following properties:

=over

=item file - string

Name of the uploaded archive

=item temp_file - string

Name of the archive as stored on disk.

=item args - Hashref

Additional data for the restore.

=back

=head3 THROWS

=over

=item When the requested archive does not exist on disk.

=item When the requested archive is not a file.

=back

=cut

sub restore_one_callback {
    my ( $self, %args ) = @_;
    my ( $filename, $temp_file, $args ) = @args{qw(file temp_file args)};

    my ( $untar_pid, $untar_fh ) = $self->_start_untar_archive( $temp_file, $args );

    # TODO: Change this to background the process in DUCK-1069
    # We can then wait for some earlier milestone and handle the
    # final state stuff in a fully backgrounded process.
    $self->_finish(
        pid       => $untar_pid,
        fh        => $untar_fh,
        directory => $args->{directory},
    );

    return 1;
}

=head2 INSTANCE->_start_untar_archive(ARCHIVE, ARGS) [PRIVATE]

Helper to start the untar of an archive in the background.

=head3 ARGUMENTS

=over

=item ARCHIVE - string

Path to the archive file.

=item ARGS - hashref

Additional arguments to the untar process.

=back

=head3 RETURNS

List with the following items: (PID, FH)

=over

=item PID - number

PID of the child process started to untar the archive.

=item FH - handle to the pipe where the child message are reported in the parent.
The caller should monitor this file handle for serialized C<Cpanel::Background::Logger::Frame>
formatted messages.

=back

=head3 THROWS

=over

=item When the child process can not be started.

=back

=cut

sub _start_untar_archive {
    my ( $self, $archive, $args ) = @_;

    $self->log->info(
        'untar',
        {
            archive     => $archive,
            description => locale()->maketext( 'The system is extracting the “[_1]” archive file.', $archive ),
        }
    );

    my ( $archive_pid, $archive_fh );
    if ( $archive_pid = open( $archive_fh, '-|' ) ) {

        # parent
        return ( $archive_pid, $archive_fh );
    }
    elsif ( defined $archive_pid ) {
        $self->_handle_untar_archive( $archive, $args );
    }
    else {
        my $error    = $!;
        my $filename = $self->log->data('file');
        logger()->error("The system failed to extract the files from the $filename backup file because it could not fork the child process with the error $error.");
        die Cpanel::Exception->create(
            'The system failed to extract the files from the “[_1]” backup file.',
            [$filename]
        );
    }

    return;
}

=head2 INSTANCE->_handle_untar_archive(ARCHIVE, ARGS) [PRIVATE]

Background process handler for untaring the archive to disk. This is the
routine for the child process. It does not return, it only exits.

=head3 ARGUMENTS

=over

=item ARCHIVE - string

Full path to the archive.

=item ARGS - hashref

Arguments to untar

=back

=cut

sub _handle_untar_archive {
    my ( $self, $archive, $args ) = @_;

    local $SIG{TERM} = \&_exit_child;

    # child
    eval {    # prevent child escaping into parent code
              # wait for the pipe to the parent be ready to write.
        my $select = IO::Select->new( \*STDOUT );
        if ( my @ready = $select->can_write(100) ) {
            eval {
                Cpanel::Untar::untar_to_directory(
                    $archive,
                    $args->{directory},
                    notice_fh          => \*STDOUT,
                    notice_formatter   => \&Cpanel::Background::Log::FrameFormatter::format,
                    user               => $Cpanel::user,
                    truncate_path      => "",
                    ignore_unsupported => 1,
                    verbose            => $self->verbose,
                );
            };
            if ( my $exception = $@ ) {
                $self->log->error( 'restore_failed', { description => Cpanel::Exception::get_string_no_id($exception) } );
                exit(1);    ## no critic(Cpanel::NoExitsFromSubroutines)
            }
        }
        else {
            my $exception = $!;
            if ( $exception && $exception == EINTR ) {
                $self->log->debug(
                    'restore_failed',
                    { description => locale()->maketext('A system administrator interrupted the file restoration.') }
                );
                exit(1);
            }
            if ($exception) {
                $self->log->error(
                    'restore_failed',
                    {
                        description => locale()->maketext(
                            'The system failed to extract the files from the archive file due to the following error: [_1]',
                            $exception
                        )
                    }
                );
                exit(1);
            }
        }
    };

    exit( $@ ? 1 : 0 );
}

=head2 INSTANCE->_finish(ARGS) [PRIVATE]

Wait for the archive to finish extracting and log the finish state.

=head3 ARGUMENTS

=over

=item ARGS - hash

With the following options:

=over

=item pid - the pid of the child process to wait on.

=item fh - the output stream from the child process.

=back

=back

=cut

sub _finish {
    my ( $self, %args ) = @_;
    my ( $pid,  $fh )   = @args{qw(pid fh)};

    $self->process_output_stream_line_by_line( $fh, is_serialized => 1 );

    _waitpid( $pid, 0 );

    close($fh);

    $self->log->done(
        'restore_done',
        {
            description => locale()->maketext(
                'The system successfully restored the “[_1]” directory from the backup file “[_2]”.',
                $args{directory},
                $self->log->data('file'),
            )
        }
    );

    return 1;
}

=head2 _waitpid(PID, FLAGS) [TESTS]

Helper to wait until children are done.

=cut

sub _waitpid {
    return waitpid( $_[0], $_[1] );
}

=head2 _exit_child() [PRIVATE]

Helper for SIG TERM in child processes.

=cut

sub _exit_child {

    # so the child can not escape to parent code.
    exit 1;
}

1;
