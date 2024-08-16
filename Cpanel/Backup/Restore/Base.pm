
# cpanel - Cpanel/Backup/Restore/Base.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Backup::Restore::Base;

use strict;
use warnings;

use Cpanel::Autodie           ();
use Cpanel::AdminBin          ();
use Cpanel::Alarm             ();
use Cpanel::Background::Log   ();
use Cpanel::Exception         ();
use Cpanel::ForkAsync         ();
use Cpanel::Gunzip            ();
use Cpanel::Path::Homedir     ();
use Cpanel::Path::Resolve     ();
use Cpanel::PwCache           ();
use Cpanel::Validate::Homedir ();
use IO::Select                ();

use Cpanel::Imports;

use Errno qw[EINTR ENOENT];

use constant {
    DEFAULT_RESTORE_TIMEOUT => 7200,        # 2 hours in seconds
    BUFFER_SIZE             => 65535,
    OUTPUT_BUFFER_SIZE      => 1024,
    MAX_OUTPUT_SIZE         => 64 * 1024,
};

=head1 MODULE

C<Cpanel::Backup::Restore::Base>

=head1 DESCRIPTION

C<Cpanel::Backup::Restore::Base> provides common services used by various restore
modules.

=head1 SYNOPSIS

  package Cpanel::Backup::Restore::Foo;

  use base qw(Cpanel::Backup::Restore::Base);

  sub new {
      my ( $class, %options ) = @_;
      my $self = $class->SUPER::new(%options);
      return $self;
  }

  sub restore {
     my ( $self, $files, %options ) = @_;
     $self->validate_files_parameter($files);
     ...
     return $self->log();
  }

=head1 CONSTRUCTOR

=cut

sub new {
    my ( $class, %options ) = @_;
    my $self = {};
    $self->{timeout} = $options{timeout} // DEFAULT_RESTORE_TIMEOUT;
    $self->{verbose} = $options{verbose} // 0;

    bless $self, $class;
    $self->_create_log( $options{type} );
    return $self;
}

=head1 PROPERTIES

=head2 log - Cpanel::Background::Log [GETTER]

Used to generate log entries for the long running process.

=cut

sub log {
    my $self = shift;
    die 'log is a getter' if @_;    # Programmer error
    return $self->{log};
}

=head2 timeout - number [GETTER]

Number of seconds to allow the restore to run before timing it out.

=cut

sub timeout {
    my $self = shift;
    die 'timeout is a getter' if @_;    # Programmer error
    return $self->{timeout};
}

=head2 homedir - string [GETTER]

Full path to the home directory for the user.

=cut

sub homedir {
    my $self = shift;
    die 'homedir is a getter' if @_;    # Programmer error

    if ( !defined $self->{homedir} ) {
        $self->{homedir} = Cpanel::Path::Homedir::get_homedir();
    }
    return $self->{homedir};
}

=head2 username() [GETTER]

Property to get the current username.

=head3 RETURNS

string - name of the current user.

=cut

sub username {
    my $self = shift;
    die 'username is a getter' if @_;    # Programmer error
    return $Cpanel::user // Cpanel::PwCache::getusername();
}

=head2 INSTANCE->verbose - Boolean [GETTER]

Whether to print out more verbose output.

=cut

sub verbose {
    my $self = shift;
    die 'verbose is a getter' if @_;     # Programmer error
    return $self->{verbose};
}

=head1 METHODS

=head2 INSTANCE->validate_files_parameter(FILES) [PROTECTED]

Validate the files parameter if it is defined.

=over

=item * Parameter is optional.

=item * If defined, it must be an array.

=item * Each item of the array must be a valid file on disk.

=back

=head3 THROWS

=over

=item When the parameter is defined, but not an array.

=item When the parameter is defined, but one of the elements is not present on disk.

=back

=cut

sub validate_files_parameter {
    my ( $self, $files ) = @_;

    return if !defined $files;

    die Cpanel::Exception::create(
        'InvalidParameter',
        'The “[_1]” parameter must be an array reference if passed to this method.', ['files']
    ) if ref $files ne 'ARRAY';

    die Cpanel::Exception::create(
        'InvalidParameter',
        'The “[_1]” parameter must be an array reference with at least one valid archive if passed to this method.', ['files']
    ) if ref $files eq 'ARRAY' && !@$files;

    foreach my $file (@$files) {
        my $exists = -e $file ? 1 : 0;
        die Cpanel::Exception::create(
            'InvalidParameter',
            'The “[_1]” file must exist on disk.',
            [$file],
        ) if !$exists;
    }

    return;
}

=head2 INSTANCE->create_alarm(KIND, MESSAGE) [PROTECTED]

Create an alarm based on the properties.

=head3 ARGUMENTS

=over

=item KIND - string

Kind of restore taking place. Used in the error log generation only.

=item MESSAGE - string | code

User message to log when the timeout occurs. Should be localized. If code,
it the function should return the message.

=back

=cut

sub create_alarm {
    my ( $self, $kind, $message ) = @_;
    return Cpanel::Alarm->new(
        $self->timeout,
        sub {
            if ( $self->log->is_open() ) {
                my $msg = ref $message eq 'CODE' ? $message->() : $message;
                $self->log->error( 'timeout', { description => $msg } );
                $self->log->close();
                die( 'The ' . $kind . ' restores took longer than ' . $self->timeout . ' seconds. The log for the restore up to this point is located in ' . $self->log->path() );
            }
            else {
                if ( my $path = $self->log->path() ) {
                    die( 'The ' . $kind . ' restores took longer than ' . $self->timeout . ' seconds. The log for the restore up to this point is located in ' . $path );
                }
                die( 'The ' . $kind . ' restores took longer than ' . $self->timeout . ' seconds.' );
            }
        }
    );
}

=head2 INSTANCE->process_output_stream_line_by_line(FH, is_serialized => ...) [PROTECTED]

Processes the output stream from the pipe. It will write new log entries for each line
that comes from the output stream.

=head3 ARGUMENTS

=over

=item fh - File handle

Stream to read from.

=item args - Hash

With the following options:

=over

=item is_serialized - Boolean

If true, each line from the stream is already a serialized Cpanel::Background::Log::Frame. Otherwise, the
line is treated as a text message to be packaged into a log entry.

=back

=back

=cut

sub process_output_stream_line_by_line {
    my ( $self, $fh, %args ) = @_;
    my $is_serialized = $args{is_serialized} // 0;
    my $buffer        = readline($fh);
    while ( defined $buffer ) {
        if ($is_serialized) {
            $self->log()->write_raw($buffer);
        }
        else {
            $self->log()->debug( 'restoring', { description => $buffer } );
        }
        $buffer = readline($fh);
    }
    return;
}

=head2 _adminrun_or_die()

Run the adminbin call. If there are any failures, die.

=head3 RETURNS

Any data returned from the run_adminbin_with_status in the data field.

=head3 THROWS

Whenever the adminbin reports a failure.

=cut

sub adminrun_or_die {
    my ( $self, @args ) = @_;

    my $adminrun = Cpanel::AdminBin::run_adminbin_with_status(@args);
    if ( !$adminrun->{status} ) {
        chomp @{$adminrun}{qw( error statusmsg )};
        die Cpanel::Exception->create_raw( $adminrun->{error} || $adminrun->{statusmsg} );
    }

    return $adminrun->{data};
}

=head2 INSTANCE->_create_log(DIR) [PRIVATE]

Create a background log object to capture all the events from the background processes.

=head3 ARGUMENTS

=over

=item DIR - string

Subdirectory to create the log in.

=back

=head3 RETURNS

Cpanel::Background::Log instance.

=cut

sub _create_log {
    my ( $self, $dir ) = @_;
    die 'dir parameter missing' if !defined $dir || $dir eq '';    # Programmer error

    my $homedir = $self->homedir();
    my $path    = "$homedir/.cpanel/logs/$dir";
    $self->{log} = Cpanel::Background::Log->new( { path => $path } );
    return;
}

=head2 INSTANCE->normalize_path(PATH)

Adjust paths with .. or . to an absolute path.

=head3 ARGUMENTS

=over

=item PATH - string

The path to normalize.

=back

=head3 RETURNS

=over

=item string - The normalized path if successful.

=back

=head3 THROWS

=over

=item When the path cannot be normalized.

=item When the path is not in the user's home directory.

=back

=cut

sub normalize_path {
    my ( $self, $path ) = @_;

    $path = Cpanel::Path::Resolve::resolve_path($path);

    Cpanel::Validate::Homedir::path_is_in_homedir_or_die($path);

    return $path;
}

=head2 INSTANCE->normalize_paths(PATHS)

Normalize all the paths in the passed-in array. It will also remove any empty elements from the array.

=head3 PATHS - array ref

Optional, Paths to normalize.

=head3 RETURNS

array ref with the normalized paths if passed an array.

=cut

sub normalize_paths {
    my ( $self, $paths ) = @_;
    if ( $paths && ref $paths eq 'ARRAY' ) {
        my @safe_paths;
        foreach my $path (@$paths) {
            next if $path eq '';
            push @safe_paths, $self->normalize_path($path);
        }
        return \@safe_paths;
    }
    return;
}

=head2 INSTANCE->account_has_domain_or_die(DOMAIN)

Validate that the current logged in cPanel user owns the domain.

=head3 ARGUMENTS

=over

=item domain - string

Domain to check against the list of domains owned by a user.

=back

=head3 THROWS

=over

=item When the domain is not owned by the current user.

=back

=cut

sub account_has_domain_or_die {
    my ( $self, $domain ) = @_;

    return 1 if grep( /^\Q$domain\E$/i, @Cpanel::DOMAINS );

    die Cpanel::Exception->create(
        'The backup is for the “[_1]” domain not owned by the current account.',
        [$domain]
    );
}

=head2 INSTANCE->gunzip_archive(ARCHIVE, LOG)

Gunzip the archive to the pipe file handle stream.

=head3 ARGUMENTS

=over

=item ARCHIVE - string

Full path to the archive to gunzip.

=item LOG - Cpanel::Background::Log

Log object used to capture meaningful events for the restore.

=back

=head3 RETURNS

List with the following items: (PID, FH)

=over

=item PID - pid

The pid for the child process that is reading the archive into the output stream.

=item FH - filehandle

File handle to the pipe for the output stream.

=back

=head3 THROWS

=over

=item When the child process for the pipe cannot be created.

=back

=cut

sub gunzip_archive {
    my ( $self, $archive ) = @_;

    my $filename = $self->log->data('file');
    $self->log->info(
        'gunzip',
        {
            archive     => $archive,
            description => locale()->maketext( 'The system is extracting the “[_1]” backup file.', $filename ),
        }
    );

    _pipe( my $archive_fh, my $child_wr ) or die "gunzip_archive: pipe error $!";
    my $archive_pid = Cpanel::ForkAsync::do_in_child_quiet(
        sub {
            close $archive_fh;
            _handle_gunzip( $child_wr, $archive, $self->log );
        }
    );

    close $child_wr;

    return ( $archive_pid, $archive_fh );
}

sub _pipe {    # for testing purpose
    goto \&CORE::pipe;
}

# Child process for gunzipping the file
sub _handle_gunzip {
    my ( $output_fh, $archive, $log ) = @_;

    local $SIG{TERM} = \&_exit_child;

    # wait for the pipe to be ready to write
    my $select = IO::Select->new($output_fh);
    if ( my @ready = $select->can_write(10) ) {

        # gunzip the uncompressed file content to the pipe
        eval { Cpanel::Gunzip::gunzip( $archive, $output_fh ) };
        if ( my $exception = $@ ) {
            $log->error( 'restore_failed', { description => Cpanel::Exception::get_string_no_id($exception) } );
            return 0;
        }
    }
    else {
        if ( $!{EINTR} ) {
            $log->debug(
                'restore_failed',
                { description => locale()->maketext('A system administrator interrupted the restoration.') }
            );
            return 0;
        }
        elsif ($!) {
            my $exception = $!;
            $log->error(
                'restore_failed',
                {
                    description => locale()->maketext(
                        'The system failed to extract files from the archive because of the following error: [_1]',
                        $exception
                    )
                }
            );
            return 0;
        }
        else {
            $log->error(
                'restore_failed',
                {
                    description => locale()->maketext(
                        'The system failed to extract files from the archive because the restore process was not ready in 10 seconds.',
                    )
                }
            );
            return 0;
        }
    }

    return 1;
}

=head2 _exit_child()

Helper for SIG TERM in child processes.

=cut

sub _exit_child {

    # so the child cannot escape to parent code.
    exit 1;    ## no critic (exit TERM handler in child
}

=head2 copy_file_if_exists(FROM, TO)

Copy the contents of the FROM file to the TO file.

=head3 ARGUMENTS

=over

=item FROM - string

Path to the file to read contents from.

=item TO - string

Path to the file to write contents to.

=back

=cut

sub copy_file_if_exists {
    my ( $self, $from, $to ) = @_;
    return if !defined $from || !defined $to;

    open( my $in_fh, '<', $from ) or return;
    Cpanel::Autodie::open( my $out_fh, '>', $to );
    while ( !eof($in_fh) ) {
        print {$out_fh} <$in_fh> or die $!;
    }
    Cpanel::Autodie::close($out_fh);
    Cpanel::Autodie::close($in_fh);
    return;
}

1;
