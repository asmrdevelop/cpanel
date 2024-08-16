
# cpanel - Cpanel/Backup/Restore/EmailFilters.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Backup::Restore::EmailFilters;

use strict;
use warnings;

use parent qw(Cpanel::Backup::Restore::Base);

use Cpanel::Autodie          ();
use Cpanel::Email::Filter    ();
use Cpanel::Exception        ();
use Cpanel::Gunzip           ();
use Cpanel::FileUtils::Write ();
use Cpanel::PipeHandler      ();
use Cpanel::Security::Authz  ();
use Cpanel::Upload           ();
use Cpanel::YAML::Check      ();
use IO::Select               ();

use Cpanel::Imports;

use Errno qw[EINTR ENOENT];

use constant {
    RESTORE_TIMEOUT => 7200,    # 2 hours in seconds
};

=head1 MODULE

C<Cpanel::Backup::Restore::EmailFilters>

=head1 DESCRIPTION

C<Cpanel::Backup::Restore::EmailFilters> provides a class for running restores of
email filters. Note only global email filters can be restored from this system.

The system supports the following file formats:

=over

=item * filter_info.{user}.yaml.gz - compressed YAML filter configuration for an account.

=item * filter_info.{user}.yaml - non-compressed YAML filter configuration for an account

=back

For these, observe the following:

=over

=item The {user} must match the current cPanel user's username.

=back

=head1 SYNOPSIS

  use Cpanel::Backup::Restore::EmailFilters();
  my $restore = Cpanel::Backup::Restore::EmailFilters->new();

  # Restore all the filters for a user
  $restore->restore([
    '/home/cpuser/backups/filter_info.cpuser.yaml.gz'
  ]);

=head1 CONSTRUCTOR

=head2 new(timeout => ...)

Create a new instance of C<Cpanel::Backup::Restore::EmailFilters>

=head3 ARGUMENTS

=over

=item timeout - number

Number of seconds until the restore times out. Defaults to 7200 seconds (2 hours). Set to 0 to disable the timeout.

=item verbose - Boolean

Generate more details of what is being restored.

=back

=head3 RETURNS

C<Cpanel::Backup::Restore::EmailFilters>

=cut

sub new {
    my ( $class, %options ) = @_;
    $options{timeout} //= RESTORE_TIMEOUT;
    $options{type} = 'restore-email-filters';

    my $self = $class->SUPER::new(%options);

    $self->{config_path} = Cpanel::Email::Filter::_fetchfilterstore();

    return $self;
}

=head1 PROPERTIES

=head2 INSTANCE->config_path - string

Get the current configure path for filters.

=cut

sub config_path {
    my $self = shift;
    die 'config_path is a getter' if @_;    # Programmer error
    return $self->{config_path};
}

=head2 INSTANCE->config_backup_path - string

Get the path for the configure path backup file.

=cut

sub config_backup_path {
    my $self = shift;
    die 'config_backup_path is a getter' if @_;    # Programmer error
    return $self->{config_path} . '.bak';
}

=head1 FUNCTIONS

=head2 INSTANCE->restore(FILES, OPTIONS)

Restores the email filter archives.

=head3 ARGUMENTS

=over

=item FILES - arraryref of strings

Optional. Each string is a path to a filter archive containing the filter configuration
to restore.

B<Note:> Though this system can process multiple filter backup files, it only makes sense
to restore a single one since it contains all the filters for a cPanel account.

B<Note:> If this argument is not provided, then it is assumed that the files were uploaded to
the server instead. The backup files will be collected from the FORM upload system
in this case.

=back

=head3 RETURNS

Cpanel::Background::Log instance with the complete list of events processed during the restore.

=cut

sub restore {
    my ( $self, $files ) = @_;
    Cpanel::Security::Authz::verify_not_root();

    $files = $self->normalize_paths($files);
    $self->validate_files_parameter($files);

    my $alarm = $self->create_alarm(
        'files',
        locale()->maketext('The system failed to restore the email filters due to a timeout.')
    );

    local $SIG{PIPE} = \&Cpanel::PipeHandler::pipeBGMgr;

    Cpanel::Upload::process_files(
        sub {
            $self->restore_one_callback(@_);
        },
        $files,
        {
            log     => $self->log(),
            verbose => $self->verbose,
        }
    );

    $self->log()->close();

    return $self->log();
}

=head2 INSTANCE->restore_one_callback(file => ..., temp_file => ..., args => ...)

Method that restores a single filter backup file.

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

=item When the archive is not a gzip file but has the .gz extension

=item When the file cannot be opened.

=item When the file format is not recognized.

=item When the file name has the wrong username in the name.

=item When the file name has a domain not owned by the account. (Legacy Only)

=item When the filters cannot be installed. (Reasons will vary)

=back

=cut

sub restore_one_callback {
    my ( $self,     %args )      = @_;
    my ( $filename, $temp_file ) = @args{qw(file temp_file)};

    my ( $type, $user, $yaml, $extension ) = split( /\./, $filename );
    $self->_ensure_archive_type_or_die( $type, $user, $yaml, $extension );
    $self->_ensure_same_user_or_die($user);

    my ( $pid, $archive_content_fh );
    if ( $filename =~ m/\.gz$/i ) {
        Cpanel::Gunzip::is_valid_or_die($temp_file);
        ( $pid, $archive_content_fh ) = $self->gunzip_archive($temp_file);
    }
    else {
        Cpanel::Autodie::open( $archive_content_fh, '<', $temp_file );
    }

    if ( !$archive_content_fh ) {
        die Cpanel::Exception->create(
            'The system failed to open the “[_1]” file.',
            [$filename]
        );
    }

    my $content_ref = $self->_slurp_content( $archive_content_fh, $pid );
    if ( !$content_ref || ref $content_ref ne 'SCALAR' ) {
        die Cpanel::Exception->create(
            'The system failed to read the the email filter from the backup.',
            [$filename]
        );
    }

    if ( Cpanel::YAML::Check::is_yaml($content_ref) ) {
        eval {
            $self->_preserve_config();
            $self->_write_config($content_ref);

            my $fstore = Cpanel::Email::Filter::_fetchfilter( $self->config_path );

            $self->_validate_filters($fstore);
            $self->_ensure_email_database();
            $self->_install_filters_for_user( $fstore, $filename );
        };
        if ( my $exception = $@ ) {
            $self->_rollback_config();
            die $exception;
        }
    }
    else {
        die locale()->maketext('The file is not a recognized email filter backup format.');
    }

    return 1;
}

=head2 INSTANCE->_write_config(CONTENT_REF) [PRIVATE]

Write the user's filter configuration file to $home/.cpanel/...

=head3 ARGUMENTS

=over

=item CONTENT_REF - string ref

Filter configuration.

=back

=head3 THROWS

=over

=item When the file cannot be opened for writing.

=item When the file cannot be written.

=back

=cut

sub _write_config {
    my ( $self, $content_ref ) = @_;
    Cpanel::FileUtils::Write::overwrite( $self->config_path, $$content_ref, 0644 );
    return;
}

=head2 INSTANCE->_preserve_config() [PRIVATE]

Save a backup of the user's filter configuration so we can roll it back if something fails.

=cut

sub _preserve_config {
    my ($self) = @_;
    $self->log->debug( 'restore_checkpoint', { description => locale()->maketext('Saving the current email filter configuration for recovery in case of restore failure.') } );

    local $!;
    link( $self->config_path, $self->config_backup_path );
    if ( $! && !( $!{ENOENT} ) ) {
        die $!;
    }
    return;
}

=head2 INSTANCE->_rollback_config() [PRIVATE]

Roll back the user's filter configuration to what it was before we started.

=cut

sub _rollback_config {
    my ($self) = @_;
    $self->log->debug( 'restore_rollback', { description => locale()->maketext('Recovering the previous email filter configuration.') } );
    Cpanel::Autodie::rename_if_exists( $self->config_backup_path, $self->config_path );
    return;
}

=head2 INSTANCE->_commit_config() [PRIVATE]

Clean up the backup file for the configuration.

=cut

sub _commit_config {
    my ($self) = @_;
    $self->log->debug( 'restore_commit', { description => locale()->maketext('Cleaning up the rollback check point.') } );
    Cpanel::Autodie::unlink_if_exists( $self->config_backup_path );
    return;
}

=head2 INSTANCE->_validate_filters(STORE) [PRIVATE]

Validate that there are filters in the backup. If not we don't want to proceed.

=head3 ARGUMENTS

=over

=item STORE

Deserialized filter storage.

=back

=cut

sub _validate_filters {
    my ( $self, $store ) = @_;

    # Do some minor validation before creating the necessary files and folders
    if ( !( $store && $store->{filter} && scalar @{ $store->{filter} } ) ) {
        $self->_rollback_config();
        die Cpanel::Exception->create('The backup did not contain any email filters. The original email filter configuration was recovered.');
    }

    return;
}

=head2 INSTANCE->_install_filters_for_user(STORE, FILENAME) [PRIVATE]

Install the user's filters from the stored configuration.

=head3 ARGUMENTS

=over

=item STORE - hashref

Deserialized filter storage.

=item FILENAME - string

Name of the archive being restored.

=back

=cut

sub _install_filters_for_user {
    my ( $self, $store, $filename ) = @_;

    ## sending an $account of undef means _store_exim_filter stores the
    ##   Exim filters in each of $Cpanel::user's @Cpanel::DOMAINS
    my ( $ok, $message ) = Cpanel::Email::Filter::_store_exim_filter( undef, $store );
    if ($ok) {
        $self->log->done( 'restore_filter', { description => locale()->maketext( 'The system successfully restored the email filters from the “[_1]” backup.', $filename ) } );
        $self->_commit_config();
    }
    else {
        $self->log->error(
            'restore_filter',
            {
                description => locale()->maketext(
                    'The system failed to restore the email filters because of the following error: [_1]',
                    $message,
                )
            }
        );
        $self->_rollback_config();
    }

    return 1;
}

=head2 INSTANCE->_ensure_email_database() [PRIVATE]

Make sure the email system is initialized.

=cut

sub _ensure_email_database {
    my ($self) = @_;

    # Make sure the /etc/vfilter files exist otherwise
    # the filters will not be put into /etc/vfilters by _store_exim_filter
    $self->adminrun_or_die( 'mx', 'ENSUREEMAILDATABASES', $Cpanel::CPDATA{'DNS'} );
    return;
}

=head2 INSTANCE->_slurp_content(FH, PID) [PRIVATE]

Read all the content from the file handle.

=head3 ARGUMENTS

=over

=item FH - file handle

Handle to the file to read from.

=item PID - pid

Background process id if any.

=back

=head3 RETURNS

string ref - Complete contents of the file as a single string.

=cut

sub _slurp_content {
    my ( $self, $fh, $pid ) = @_;
    my $content = '';

    my $select = IO::Select->new($fh);
    if ( my @ready = $select->can_read(10) ) {
        if ( !eof($fh) ) {
            local $/;
            $content = <$fh>;
        }
    }
    else {
        if ( $!{EINTR} ) {
            $self->log->debug(
                'restore_failed',
                {
                    description => locale()->maketext(
                        'A system administrator interrupted the email filter restoration.',
                    )
                }
            );
        }
        elsif ( my $exception = $! ) {
            $self->log->error(
                'restore_failed',
                {
                    description => locale()->maketext(
                        'The system failed to restore the email filter configuration with the following error: [_1]',
                        $exception
                    )
                }
            );
        }
        return;
    }

    waitpid( $pid, 0 ) if defined $pid;

    close($fh);

    return \$content;
}

=head2 INSTANCE->_ensure_same_user_or_die(USER) [PRIVATE]

Validate that the user matches the current logged in cPanel user.

=head3 ARGUMENTS

=over

=item USER - string

User to check against the current user.

=back

=head3 THROWS

=over

=item When the user is not the current user.

=back

=cut

sub _ensure_same_user_or_die {
    my ( $self, $user ) = @_;
    die Cpanel::Exception::create( 'MissingParameter', ['user'] ) if !defined $user;
    return 1                                                      if $self->username() eq $user;

    die Cpanel::Exception->create('The email filters in the backup are not for the current user.');
}

=head2 INSTANCE->_ensure_archive_type_or_die(TYPE, USER, YAML, EXTENSION)

Validate that the type is what we expect.

=head3 ARGUMENTS

=over

=item TYPE - string

Must be 'filter_info'.

=item USER - string

Must be defined

=item YAML - string

Must by 'yaml'

=item EXTENSION - string

Optional, if provided must be gz.

=back

=cut

sub _ensure_archive_type_or_die {
    my ( $self, $type, $user, $yaml, $extension ) = @_;
    if (   !defined $type
        || $type ne 'filter_info'
        || !defined $user
        || $user eq ''
        || !defined $yaml
        || $yaml ne 'yaml'
        || ( defined $extension && $extension ne 'gz' ) ) {
        die Cpanel::Exception->create(
            'The backup name is not formatted correctly. It should be similar to “[_1]”.',
            ['filter_info.cpuser.yaml.gz']
        );
    }
    return;
}

1;
