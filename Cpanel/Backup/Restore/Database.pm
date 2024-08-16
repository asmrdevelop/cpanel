
# cpanel - Cpanel/Backup/Restore/Database.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Backup::Restore::Database;

use strict;
use warnings;

use Cpanel::Imports;

use Cpanel::AdminBin            ();
use Cpanel::AdminBin::Call      ();
use Cpanel::Alarm               ();
use Cpanel::Autodie             ();
use Cpanel::Background::Log     ();
use Cpanel::DB                  ();
use Cpanel::DbUtils             ();
use Cpanel::Exception           ();
use Cpanel::MysqlDumpParse      ();
use Cpanel::MysqlUtils::TempEnv ();
use Cpanel::PwCache             ();
use Cpanel::PipeHandler         ();
use Cpanel::Rand::Get           ();
use Cpanel::SafeRun::Object     ();
use Cpanel::Upload              ();
use Cpanel::Gunzip              ();
use IO::Select                  ();
use Cpanel::Validate::DB::Name  ();

use Errno qw[EINTR];

=head1 MODULE

C<Cpanel::Backup::Restore::Database>

=head1 DESCRIPTION

C<Cpanel::Backup::Restore::Database> provides tooling to restore databases from
either .sql or .sql.gz files.

The database name is derived first from the SQL script content. If the database
name is not present in the early part of the SQL script, the database name is
parsed out of the file name.

If the restore takes longer than 7200 seconds, the restore times out.

=cut

use constant {
    RESTORE_DATABASE_TIMEOUT => 7200,
    BUFFER_SIZE              => 65535,
    OUTPUT_BUFFER_SIZE       => 1024,
    MAX_OUTPUT_SIZE          => 64 * 1024,
};

=head1 FUNCTIONS

=head2 restore_databases(FILES, OPTIONS)

Restore

=head3 ARGUMENTS

=over

=item FILES - array of strings

Optional, paths to a file on disk to restore. Only provide this from the command line. When provided each path must exist on the server already.

DO NOT USE THIS ARGUMENT WHEN CALLING THE API FROM A WEB PAGE WITH A FILE UPLOAD CONTROL.

=item OPTIONS - hash

Where the following options may be provided:

=over

=item timeout - number

Maximum number of seconds to run the restore before giving up. Defaults to 7200 seconds (2 hours).

=back

=back

=head3 RETURNS

=over

=item log - Cpanel::Background::Log

Information about where the output log is written. This is most useful for fully
asynchronous parts of the restore. It will be used by the SSE/Websocket interface
that will be developed later.

=back

=cut

sub restore_databases {
    my ( $files, %options ) = @_;
    die Cpanel::Exception::create(
        'InvalidParameter',
        'The “[_1]” parameter must be an array reference if passed to this method.', ['files']
    ) if $files && ref $files ne 'ARRAY';

    my $log     = _create_log();
    my $timeout = $options{timeout} // RESTORE_DATABASE_TIMEOUT;

    my $alarm = Cpanel::Alarm->new(
        $timeout,
        sub {
            if ( $log->is_open() ) {
                $log->error( 'timeout', { description => locale()->maketext('The system failed to restore the database due to a timeout.') } );
                $log->close();
                die( 'The database restores took longer than ' . $timeout . ' seconds. The log for the restore up to this point is located in ' . $log->path() );
            }
            else {
                die( 'The database restores took longer than ' . $timeout . ' seconds.' );
            }
        }
    );

    local $SIG{PIPE} = \&Cpanel::PipeHandler::pipeBGMgr;

    my $mysqlhost = _adminrun_or_die( 'cpmysql', 'GETHOST' );
    local $ENV{'REMOTE_MYSQL_HOST'} = $mysqlhost if $mysqlhost;

    $log = Cpanel::Upload::process_files( \&restore_database, $files, { log => $log } );

    $log->close();

    return $log;
}

=head2 restore_database(temp_file => ..., file => ..., log => ...)

Restore a single database

=head3 ARGUMENTS

Hash with the following properties:

=over

=item temp_file - string

Full path to the file on the server's file-system. Must be accessible by the
logged in cPanel user.

=item file - string

Name of the file on the original file-system.

=item log - Cpanel::Background::Log

Tool used to log info, warnings and errors as the backup proceeds. This will be
more useful once we add the SSE/Websocket interface and fully background the
restore.

=back

=head3 RETURNS

Boolean - 1 when successful, dies otherwise.

=head3 THROWS

=over

=item When the path passed does not exist.

=item When the path passed is not a file.

=item When a .gz file is passed, but it's not a valid archive.

=item When the .sql or .sql.gz file can not be opened.

=item When the archive can not be decompressed.

=item When starting any of the intermediate processes fails.

=item When one of the pipes can not be opened.

=back

=cut

sub restore_database {
    my %args = @_;

    my ( $filename, $temp_file, $log ) = @args{qw(file temp_file log)};
    my $homedir = _get_homedir();

    die Cpanel::Exception->create(
        'The file “[_1]” does not exist.',
        [$temp_file]
    ) if !-e $temp_file;

    die Cpanel::Exception->create(
        'The path “[_1]” is not a database backup file.',
        [$temp_file]
    ) if !-f _;

    my ( $mysql_env, $temp_database_user, $temp_database_password ) = ( undef, '', '' );

    my $final = 0;
    local $SIG{TERM} = sub {
        if ( !$final ) {
            if ($temp_database_user) {
                _remove_temp_database_user( $temp_database_user, $log );
            }

            my $message = locale()->maketext('The restore database process was terminated.');
            $log->error( 'terminate', { description => $message } );
            $log->close();

            $final = 1;

            # kill the whole process group so the child processes
            # are reaped correctly. Negative signals mean the process
            # group for perls kill() function.
            kill -15, $$;
        }
        else {
            # done cleaning up the child processes
            # we can really die now.
            die('The restore database process was terminated.');
        }
    };

    my ( $mysql_fh, $mysql_pid );
    if ( $filename =~ m/\.gz$/i ) {
        Cpanel::Gunzip::is_valid_or_die($temp_file);
        ( $mysql_pid, $mysql_fh ) = _gunzip_archive( $temp_file, $log );
    }
    else {
        Cpanel::Autodie::open( $mysql_fh, '<', $temp_file );
    }

    if ( !$mysql_fh ) {
        die Cpanel::Exception->create(
            'The system failed to open the uploaded file “[_1]”.',
            [$filename]
        );
    }

    # Peek into the stream for the database name.
    # It will be returned as the first line of the peek file handle.
    my ( $peek_pid, $peek_fh ) = _peek_for_database_name(
        file => $filename,
        fh   => $mysql_fh,
        log  => $log
    );

    # Read the first line that is the database name.
    my $db_name = <$peek_fh>;

    chomp $db_name if $db_name;
    Cpanel::Validate::DB::Name::verify_mysql_database_name($db_name);

    # Prepare the database for usage.
    my $created = _create_database( $db_name, $log );

    ( $temp_database_user, $temp_database_password ) = _create_temp_database_user( $db_name, $log );
    $mysql_env = Cpanel::MysqlUtils::TempEnv->new( host => $ENV{'REMOTE_MYSQL_HOST'}, user => $temp_database_user, password => $temp_database_password );

    my ( $fixer_pid, $fixer_fh ) = _transform_script(
        fh      => $peek_fh,
        db_user => $mysql_env->get_mysql_user(),
        log     => $log,
    );

    my ( $restore_pid, $restore_fh ) = _restore_database_from_script(
        fh        => $fixer_fh,
        db_name   => $db_name,
        mysql_env => $mysql_env,
        log       => $log,
    );

    # TODO: Change this to background the process in DUCK-1067
    # We can then wait for some earlier milestone and handle the
    # final state stuff in a fully backgrounded process.
    _finish(
        pid     => $restore_pid,
        fh      => $restore_fh,
        db_name => $db_name,
        db_user => $temp_database_user,
        log     => $log
    );

    return 1;
}

=head2 _gunzip_archive(ARCHIVE, LOG) [PRIVATE]

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

=item When the child process for the pipe can not be created.

=back

=cut

sub _gunzip_archive {
    my ( $archive, $log ) = @_;

    $log->info(
        'gunzip',
        {
            archive     => $archive,
            description => locale()->maketext( 'The system is extracting the archive “[_1]”.', $archive ),
        }
    );
    my ( $archive_pid, $archive_fh );
    if ( $archive_pid = open( $archive_fh, '-|' ) ) {

        # parent
        return ( $archive_pid, $archive_fh );
    }
    elsif ( defined $archive_pid ) {
        _handle_gunzip( $archive, $log );
    }
    else {
        my $error    = $!;
        my $filename = $log->data('file');
        logger()->error("The system failed to extract the database script from the backup file $filename because it could not fork the child process with the error $error.");
        die Cpanel::Exception->create(
            'The system failed to extract the database script from the backup file “[_1]”.',
            [$filename]
        );
    }

    return 1;
}

# Child process for gunzipping the file
sub _handle_gunzip {
    my ( $archive, $log ) = @_;

    local $SIG{TERM} = \&_exit_child;

    # child
    eval {    # prevent child escape to parent code

        # wait for the pipe to be ready to write
        my $select = IO::Select->new( \*STDOUT );
        if ( my @ready = $select->can_write(10) ) {

            # gunzip the uncompressed file content to the pipe
            eval { Cpanel::Gunzip::gunzip( $archive, \*STDOUT ) };
            if ( my $exception = $@ ) {
                $log->error( 'restore_failed', { description => $exception } );
                exit(1);
            }
        }
        else {
            my $exception = $!;
            if ( $exception && $exception == EINTR ) {
                $log->debug(
                    'restore_failed',
                    { description => locale()->maketext('A system administrator interrupted the database restoration.') }
                );
                exit(1);
            }
            if ($exception) {
                $log->error(
                    'restore_failed',
                    {
                        description => locale()->maketext(
                            'The system failed to extract the database script from the archive with the following error: [_1]',
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

=head2 _peek_for_database_name(file => ..., fh => ..., log => ...)

Scan the pipe stream in FH for the database name. This will return a new pipe stream containing the database name followed by the original data.

=head3 ARGUMENTS

Hash with the following properties:

=over

=item file - string

The name of the original file uploaded to the server.

=item fh - file handle

The input stream containing the raw SQL commands from the archive.

=item log - Cpanel::Background::Log

Log object used to capture meaningful events for the restore.

=back

=head3 RETURNS

List with the following items: (PID, FH)

=over

=item PID - pid

The pid for the child process that is reading the input stream to get the database name.

=item FH - filehandle

File handle to the pipe that will receive the stream of data from the child process.

=back

=head3 THROWS

=over

=item When the child process for the pipe can not be forked.

=back

=cut

sub _peek_for_database_name {
    my %args = @_;
    my ( $filename, $archive_fh, $log ) = @args{qw(file fh log)};

    my ( $peek_pid, $peek_fh );
    if ( $peek_pid = open( $peek_fh, '-|' ) ) {

        # parent
        return ( $peek_pid, $peek_fh );
    }
    elsif ( defined $peek_pid ) {
        _handle_peek_for_database_name(%args);
    }
    else {
        my $error    = $!;
        my $filename = $log->data('file');
        logger()->error("The system failed to identify the database name in the database script from the backup file $filename because it could not fork the child process with the error $error.");
        die Cpanel::Exception->create(
            'The system failed to identify the database name.',
        );
    }

    return 1;
}

# handler for child process that finds the database name
sub _handle_peek_for_database_name {
    my %args = @_;
    my ( $filename, $archive_fh, $log ) = @args{qw(file fh log)};

    local $SIG{TERM} = \&_exit_child;

    # child
    eval {    # prevent child escape to parent code
              # wait for the pipe to be ready to write

        my $select = IO::Select->new( \*STDOUT );
        if ( my @ready = $select->can_write(10) ) {
            my $buffer;
            my $read = _read( $archive_fh, $buffer, BUFFER_SIZE );
            if ( !defined $read ) {
                $log->error(
                    'restore_failed',
                    {
                        description => locale()->maketext(
                            'The system failed to read from the input pipe with the following error: [_1]',
                            $!
                        )
                    }
                );
                exit(1);
            }
            elsif ( !$read ) {
                $log->error(
                    'restore_failed',
                    {
                        description => locale()->maketext(
                            'The backup file “[_1]” is empty.',
                            $filename,
                        ),
                    }
                );
                exit(1);
            }
            else {
                my $db_name = _get_database_name( $filename, $buffer, $log );

                # stream out the database name.
                print STDOUT $db_name . "\n";

                # next stream out the first buffer block untouched.
                print STDOUT $buffer;

                # stream out the remaining data from the file handle.
                while ( _read( $archive_fh, $buffer, BUFFER_SIZE ) ) {
                    print STDOUT $buffer;
                }
            }
            close $archive_fh if $archive_fh;
        }
        else {
            my $exception = $!;
            if ( $exception && $exception == EINTR ) {
                $log->debug(
                    'restore_failed',
                    { description => locale()->maketext('A system administrator interrupted the database restoration.') }
                );
                exit(1);
            }
            if ($exception) {
                $log->error(
                    'restore_failed',
                    {
                        description => locale()->maketext(
                            'The system failed to identify the database name due to the following error: [_1]',
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

=head2 _get_database_name(FILE, BUFFER, LOG) [PRIVATE]

Gets the database name from either the sql content or the file name.

=head3 ARGUMENTS

=over

=item FILE - string

Original file name for the upload

=item BUFFER - string

Buffer containing some of the SQL commands from the archive.

=item LOG - Cpanel::Background::Log

Log object used to capture meaningful events for the restore.

=back

=head3 RETURNS

String containing the database name.

=cut

sub _get_database_name {
    my ( $file, $buffer, $log ) = @_;

    my $db_name = _get_database_name_from_data_if_possible($buffer);
    if ( !$db_name ) {
        require Cpanel::Encoder::URI;
        $file = Cpanel::Encoder::URI::uri_decode_str($file);    #noticed Chromium uri encodes
        my $file_name = ( split( m{/+}, $file ) )[-1];
        $file_name =~ s/(?:\.sql)?(?:\.gz)?$//;
        $db_name = $file_name;
    }

    if ( !$db_name ) {
        die Cpanel::Exception->create(
            'The file “[_1]” does not contain a database to restore.',
            $log->data('file'),
        );
    }

    $db_name = Cpanel::DB::add_prefix_if_name_and_server_need($db_name);

    $log->debug(
        'database_name',
        {
            description => locale()->maketext(
                'The system identified the database name for the backup file “[_1]” to be “[_2]”.',
                $log->data('file'),
                $db_name
            ),
            database => $db_name,
        }
    );
    return $db_name;
}

=head2 _get_database_name_from_data_if_possible(BUFFER) [PRIVATE]

Get the database name from the buffer of SQL commands if possible.

=head3 ARGUMENTS

=over

=item BUFFER - string

Raw SQL commands to look for the database name within.

=back

=head3 RETURNS

String - the database name if it can be found in the BUFFER. If not an empty string is returned.

=cut

sub _get_database_name_from_data_if_possible {
    my ($buffer) = @_;
    my $db = '';

    if ( $buffer =~ /Database:\s(.*?)\r?\n/sig ) {
        $db = $1;
    }

    chomp $db;
    $db =~ s/[\r\n`]//g;    # Database names are allowed to contain backticks but may be quoted so we remove them just in case.
    return $db;
}

=head2 _create_database(DATABASE, LOG) [PRIVATE]

Create the database if it does not already exist.

=head3 ARGUMENTS

=over

=item DATABASE - string

Name of the database to create.

=item LOG - Cpanel::Background::Log

Log object used to capture meaningful events for the restore.

=back

=head3 RETURNS

1 if the database was created, 0 if the database already exists.

=cut

sub _create_database {
    my ( $database, $log ) = @_;
    Cpanel::Validate::DB::Name::verify_mysql_database_name($database);

    require Cpanel::AdminBin::Call;

    if ( !Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'DBEXISTS', $database ) ) {

        Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'CREATE_DATABASE', $database );

        $log->info(
            'database_create',
            {
                database    => $database,
                description => locale()->maketext( 'The system created the database “[_1]” since it did not exist.', $database ),
            }
        );
        return 1;
    }
    return 0;
}

=head2 _create_temp_database_user(DATABASE, LOG) [PRIVATE]

Create a temporary database user so we don't have to know the password. This is only
needed when used from the command line.

This user will get deleted later in the process.

=head3 ARGUMENTS

=over

=item DATABASE - string

Name of the database the temporary user needs access to.

=item LOG - Cpanel::Background::Log

Log object used to capture meaningful events for the restore.

=back

=head3 RETURNS

List with the following items (USERNAME, PASSWORD) where:

=over

=item USERNAME - name of the temporary mysql user.

=item PASSWORD - password for the temporary mysql user.

=back

=cut

sub _create_temp_database_user {
    my ( $database, $log ) = @_;

    my $username;
    do {
        $username = Cpanel::DB::add_prefix_if_name_and_server_need( Cpanel::Rand::Get::getranddata( 7, [ 'a' .. 'z', '0' .. '9' ] ) );
    } until !_adminrun_or_die( 'cpmysql', 'USEREXISTS', $username );

    my $password = Cpanel::Rand::Get::getranddata(20);

    my $ret = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'CREATE_USER', $username, $password );
    $log->debug(
        'created_temp_database_user',
        {
            username    => $username,
            description => locale()->maketext( 'The system created a temporary database user “[_1]”.', $username ),
        }
    );

    $ret = Cpanel::AdminBin::Call::call( 'Cpanel', 'mysql', 'SET_USER_PRIVILEGES_ON_DATABASE', $username, $database, ['ALL'] );
    $log->debug(
        'linked_temp_database_user_to_database',
        {
            username    => $username,
            database    => $database,
            description => locale()->maketext( 'The system linked the temporary database user “[_1]” to the database “[_2]”.', $username, $database ),
        }
    );
    return ( $username, $password );
}

=head2 _remove_temp_database_user(USERNAME, LOG) [PRIVATE]

Removes the temporary MySQL database user.

=head3 ARGUMENTS

=over

=item USERNAME - string

The temp database user to remove.

=item LOG - Cpanel::Background::Log

Log object used to capture meaningful events for the restore.

=back

=cut

sub _remove_temp_database_user {
    my ( $username, $log ) = @_;

    # Everything is finished so we don't want to die here, but
    # we do want to record the error in the log and still report
    # the restore finished. We are recording it as a warning since
    # its not critical to the success of the operation.
    eval { _adminrun_or_die( 'cpmysql', 'DELUSER', $username ) };
    if ( my $exception = $@ ) {
        $log->warn(
            'exception',
            {
                description => Cpanel::Exception::get_string_no_id($exception),
            }
        );
    }
    else {
        $log->debug(
            'removed_temp_database_user',
            {
                username    => $username,
                description => locale()->maketext( 'The system removed the temporary database user “[_1]”.', $username ),
            }
        );
    }
    return 1;
}

=head2 _transform_script(fh => ..., db_user => ..., log => ...) [PRIVATE]

Adjust the definer clauses in the script to use the user in the
mysql environment object.

=head3 ARGUMENTS

=over

=item fh - file handle

Stream of SQL command to transform.

=item db_name - string

The database name we are restoring to.

=item db_user - string

Database user to use when creating the table objects with DEFINERs.

=item LOG - Cpanel::Background::Log

Log object used to capture meaningful events for the restore.

=back

=head3 RETURNS

List with the following items: (PID, FH)

=over

=item PID - pid

The pid for the child process that is reading the input stream perform the stream transformation.

=item FH - filehandle

File handle to the pipe that will receive the stream of data transformed by the child process.

=back

=head3 THROWS

=over

=item When the child process for the pipe can not be forked.

=back

=cut

sub _transform_script {
    my %args = @_;
    my ( $fh, $db_name, $db_user, $log ) = @args{qw(fh db_name db_user log)};

    my ( $def_pid, $def_fh );
    if ( $def_pid = open( $def_fh, '-|' ) ) {

        # parent
        return ( $def_pid, $def_fh );
    }
    elsif ( defined $def_pid ) {
        _handle_transform(%args);
    }
    else {
        my $error    = $!;
        my $filename = $log->data('file');
        logger()->error("The system failed to prepare the database script $filename because it could not fork the child process with the error $error.");
        die Cpanel::Exception->create('The system failed to prepare the database script.');
    }

    return 1;
}

# Child function that handles the transformation.
sub _handle_transform {
    my %args = @_;
    my ( $fh, $db_name, $db_user, $log ) = @args{qw(fh db_name db_user log)};

    local $SIG{TERM} = \&_exit_child;

    # child
    eval {    # prevent child escape to parent code

        # Transform invalid DEFINER clauses
        my $definer_regex = Cpanel::MysqlDumpParse::get_definer_re();

        my $select = IO::Select->new( \*STDOUT );
        if ( my @ready = $select->can_write(10) ) {
            while ( my $line = <$fh> ) {
                $line =~ s/$definer_regex/DEFINER=`$db_user`\@$2/g;
                print STDOUT $line;
            }
        }
        else {
            logger()->info( 'Restore of ' . $log->data('file') . ' failed in the child with the error: ' . $! );

            my $exception = $!;
            if ( $exception && $exception == EINTR ) {
                $log->debug(
                    'restore_failed',
                    {
                        description => locale()->maketext('A system administrator interrupted the database restoration.'),
                    }
                );
                exit(1);
            }
            if ($exception) {
                $log->error(
                    'restore_failed',
                    {
                        description => locale()->maketext(
                            'The system failed to prepare the database script due to the following error: [_1]',
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

=head2 _restore_database_from_script(fh => ..., mysql_env => ..., db_name => ..., log => ...) [PRIVATE]

Stream in the fixed SQL file to the mysql binary.

Stream out the output from mysql binary as the restore happens.

The output is logged as 'restoring' events in the log file.

The temporary db user is removed once the entire SQL backup is restored.

=head3 ARGUMENTS

Hash with the following properties:

=over

=item fh - filehandle

Input stream of the SQL script to run to perform the restore.

=item mysql_env - Cpanel::MysqlUtil::TempEnv

Temporary .my.cnf manager for credential for the user and database.

=item db_name - string

Name of the database to apply the script to.

=item log - Cpanel::Background::Log

Log of the steps performed.

=back

=head3 RETURNS

List with the following items: (pid, fh)

=over

=item pid - process id for the background task running the restore.

=item fh - the output filehandle for data coming from the restore process.

=back

=head3 NOTE

We are currently waiting for the restore to finish before returning. It would
be better to background this whole process so it was possible to restore
bigger backups without timing out.

=cut

sub _restore_database_from_script {
    my %args = @_;
    my ( $fh, $db_name, $mysql_env, $log ) = @args{qw(fh db_name mysql_env log)};

    $log->info( 'restoring_start', { description => locale()->maketext( 'The system is starting to restore the database backup “[_1]”.', $log->data('file') ) } );

    if ( my $mysql_pid = open( my $mysql_fh, '-|' ) ) {
        return ( $mysql_pid, $mysql_fh );
    }
    elsif ( defined $mysql_pid ) {
        _handle_restore(%args);
    }
    else {
        my $error    = $!;
        my $filename = $log->data('file');

        logger()->error("The system failed to restore the database $db_name from the backup file $filename because it could not fork the child process with the error $error.");
        die Cpanel::Exception->create(
            'The system failed to restore the database “[_1]” with the following error: [_2]',
            [ $db_name, $error ]
        );
    }

    return 1;
}

# Child process function that handles the restoration.
sub _handle_restore {
    my %args = @_;
    my ( $fh, $db_name, $mysql_env, $log ) = @args{qw(fh db_name mysql_env log)};

    local $SIG{TERM} = \&_exit_child;

    # Child
    eval {    # prevent child escape to parent code

        my $select = IO::Select->new( \*STDOUT );
        if ( my @ready = $select->can_write(10) ) {
            my $mysql_bin = Cpanel::DbUtils::find_mysql();
            my $args      = [ $mysql_env->get_mysql_params(), '-v', $db_name ];
            my $run       = Cpanel::SafeRun::Object->new(
                'program' => $mysql_bin,
                'args'    => $args,
                'stdin'   => $fh,
                'stdout'  => \*STDOUT,
            );

            if ( $run->CHILD_ERROR() ) {
                $log->error( 'restore_failed', { description => locale()->maketext( 'The system failed to execute the database script with the following errors: [_1]', $run->stderr() ) } );
                exit(1);
            }
        }
        else {
            my $exception = $!;
            if ( $exception && $exception == EINTR ) {
                $log->debug(
                    'restore_failed',
                    {
                        description => locale()->maketext(
                            'A system administrator interrupted the database restoration. The database “[_1]” may be corrupt.',
                            $db_name
                        )
                    }
                );
                exit(1);
            }
            if ($exception) {
                $log->error(
                    'restore_failed',
                    {
                        description => locale()->maketext(
                            'The system failed to restore the database “[_1]” with the following error: “[_2]”. The database “[_1]” may be corrupt.',
                            $db_name,
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

=head2 _finish(pid => ..., fh => ..., db_name => ..., db_user => ..., log => ...) [PRIVATE]

Wait for the restore to finish and then clean up the resources.

=head3 ARGUMENTS

=over

=item pid - PID

Process id for the restore background process.

=item fh - filehandle

Output stream from the restore background process.

=item db_name - string

Name of the database we are restore to.

=item db_user - string

Temporary database username if one was created. Used to remote the temporary database user.

=item log - Cpanel::Background::Log

Log of the steps performed.

=back

=cut

sub _finish {
    my %args = @_;
    my ( $pid, $fh, $db_name, $temp_database_user, $log ) = @args{qw(pid fh db_name db_user log)};

    my ( $buffer, $count, $truncate_sent ) = ( '', 0, 0 );
    while ( !eof($fh) ) {
        my $read = read( $fh, $buffer, OUTPUT_BUFFER_SIZE );
        if ($read) {
            if ( $count < MAX_OUTPUT_SIZE ) {
                $log->debug( 'restoring', { description => $buffer } );
                $count += $read;
            }
            elsif ( !$truncate_sent ) {
                $truncate_sent = 1;
                $log->debug( 'restoring', { description => '…', truncated => 1 } );
            }
        }

        # just throw away everything after the MAX_OUTPUT_SIZE is printed.
    }

    waitpid( $pid, 0 );
    my $child_exit = $? >> 8;

    close($fh);

    if ($temp_database_user) {
        _remove_temp_database_user( $temp_database_user, $log );
    }

    if ( !$child_exit ) {
        $log->done(
            'restore_done',
            {
                description => locale()->maketext(
                    'The system successfully restored the database “[_1]” from the backup file “[_2]”.',
                    $db_name,
                    $log->data('file'),
                )
            }
        );
    }
    return 1;
}

=head2 _get_homedir [PRIVATE]

Helper method to get the current user's home directory.

=cut

sub _get_homedir {
    return $Cpanel::homedir // Cpanel::PwCache::gethomedir($>);
}

=head2 _create_log()

Create a background log object to capture all the events from the background processes.

=head3 RETURNS

Cpanel::Background::Log instance.

=cut

sub _create_log {
    my $homedir = _get_homedir();
    my $path    = "$homedir/.cpanel/logs/restoredb";
    return Cpanel::Background::Log->new( { path => $path } );
}

=head2 _adminrun_or_die()

Run the adminbin call. If there are any failures, die.

=head3 RETURNS

Any data returned from the run_adminbin_with_status in the data field.

=head3 THROWS

Whenever the adminbin reports a failure.

=cut

sub _adminrun_or_die {
    my @args = @_;

    my $adminrun = Cpanel::AdminBin::run_adminbin_with_status(@args);
    if ( !$adminrun->{'status'} ) {
        chomp @{$adminrun}{qw( error statusmsg )};
        die Cpanel::Exception->create_raw( $adminrun->{'error'} || $adminrun->{'statusmsg'} );
    }

    return $adminrun->{data};
}

=head2 _exit_child()

Helper for SIG TERM in child processes.

=cut

sub _exit_child {

    # so the child can not escape to parent code.
    exit 1;
}

# For mocking only.
sub _read {
    return read( $_[0], $_[1], $_[2] );
}

1;
