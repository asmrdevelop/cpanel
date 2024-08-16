
# cpanel - Cpanel/Backup/Restore/EmailForwarders.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Backup::Restore::EmailForwarders;

use strict;
use warnings;

use strict;
use warnings;

use parent qw(Cpanel::Backup::Restore::Base);

use Cpanel::Autodie         ();
use Cpanel::ConfigFiles     ();
use Cpanel::Exception       ();
use Cpanel::Gunzip          ();
use Cpanel::Mkdir           ();
use Cpanel::PipeHandler     ();
use Cpanel::Security::Authz ();
use Cpanel::Upload          ();
use IO::Select              ();

use Cpanel::Imports;

use Errno qw[EINTR];

use constant {
    RESTORE_TIMEOUT => 7200,    # 2 hours
};

=head1 MODULE

C<Cpanel::Backup::Restore::EmailForwarders>

=head1 DESCRIPTION

C<Cpanel::Backup::Restore::EmailForwarders> provides a class for running restores of
email forwarders.

The system supports the following file formats:

=over

=item * aliases-{domain}.gz - compressed email forwarder configuration for a specific domain.

=item * aliases-{domain} - email forwarder configuration for a specific domain.

=back

For these, observe the following:

=over

=item The {domain} indicates the fully qualified domain to restore the forwarders to and must be owned by the current user.

=back

=head1 SYNOPSIS

  use Cpanel::Backup::Restore::EmailForwarders ();
  my $restore = Cpanel::Backup::Restore::EmailForwarders->new();

  # Restore the email forwarders for the domain 'domain.com'
  $restore->restore([
    '/home/cpuser/backups/aliases-domain.com.gz'
  ]);

=head1 CONSTRUCTOR

=head2 new(timeout => ...)

Create a new instance of C<Cpanel::Backup::Restore::EmailForwarders>

=head3 ARGUMENTS

=over

=item timeout - number

Number of seconds until the restore times out. Defaults to 7200 seconds (2 hours). Set to 0 to disable the timeout.

=item verbose - Boolean

Generate more details of what is being restored.

=back

=head3 RETURNS

C<Cpanel::Backup::Restore::EmailForwarders>

=cut

sub new {
    my ( $class, %options ) = @_;
    $options{timeout} //= RESTORE_TIMEOUT;
    $options{type} = 'restore-email-forwarders';

    my $self = $class->SUPER::new(%options);
    return $self;
}

=head1 PROPERTIES

=head2 INSTANCE->config_path - string

Get the current configure path for the forwarders for a domain.

=cut

sub config_path {
    my ( $self, $domain, @rest ) = @_;
    die 'Missing domain.'         if !defined $domain || $domain eq '';    # Programmer error
    die 'config_path is a getter' if scalar @rest;                         # Programmer error

    return "$Cpanel::ConfigFiles::VALIASES_DIR/$domain";
}

=head2 INSTANCE->config_backup_path - string

Get the configure backup file path for the forwarders for a domain.

=cut

sub config_backup_path {
    my ( $self, $domain, @rest ) = @_;
    die 'Missing domain.'                if !defined $domain || $domain eq '';    # Programmer error
    die 'config_backup_path is a getter' if scalar @rest;                         # Programmer error

    my $base = $self->homedir . '/.cpanel/tmp/aliases';
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $base, 0700 );
    return "$base/$domain.bak";
}

=head1 FUNCTIONS

=head2 INSTANCE->restore(FILES, OPTIONS)

Restores the email forwarder archives.

=head3 ARGUMENTS

=over

=item FILES - arraryref of strings

Optional. Each string is a path to a forwarder archive containing the forwarder configuration
for a specific domain to restore.

B<Note:> If this argument is not provided, then it is assumed that the files were uploaded to
the server instead. The backup files will be collected from the FORM upload system
in this case.

=back

=head3 RETURNS

Cpanel::Background::Log instance with the complete list of events processed during the restore.

=cut

sub restore {
    my ( $self, $files, %options ) = @_;
    Cpanel::Security::Authz::verify_not_root();

    $files = $self->normalize_paths($files);
    $self->validate_files_parameter($files);

    my $alarm = $self->create_alarm(
        'files',
        locale()->maketext('The system failed to restore the email forwarders due to a timeout.')
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

=head2 INSTANCE->restore_one_callback()

=head3 ARGUMENTS

=over

=item ARGS - hash

with the following properties:

=over

=item file - string

=item temp_file - string

=back

=back

=cut

sub restore_one_callback {
    my ( $self,     %args )      = @_;
    my ( $filename, $temp_file ) = @args{qw(file temp_file)};

    my ( $type, $domain ) = split( /-/, $filename, 2 );
    $self->_ensure_archive_type_or_die($type);

    $domain =~ s/\.gz$//;
    $self->account_has_domain_or_die($domain);

    my ( $pid, $archive_fh );
    if ( $filename =~ m/\.gz$/i ) {
        Cpanel::Gunzip::is_valid_or_die($temp_file);
        ( $pid, $archive_fh ) = $self->gunzip_archive($temp_file);
    }
    else {
        Cpanel::Autodie::open( $archive_fh, '<', $temp_file );
    }

    if ( !$archive_fh ) {
        die Cpanel::Exception->create(
            'The system failed to open the “[_1]” email forwarders backup file.',
            [$filename]
        );
    }

    # Make sure the /etc/vfilters files exist otherwise the
    # file will not be created
    $self->adminrun_or_die( "mx", 'ENSUREEMAILDATABASESFORDOMAIN', $domain );
    $self->_write_config( $domain, $archive_fh, $pid, $filename );

    return 1;
}

=head2 INSTANCE->_ensure_archive_type_or_die(TYPE)

Validate that the type is what we expect.

=head3 ARGUMENTS

=over

=item TYPE - string

Must be 'aliases'.

=back

=cut

sub _ensure_archive_type_or_die {
    my ( $self, $type ) = @_;
    if ( !$type || $type ne 'aliases' ) {
        die Cpanel::Exception->create(
            'The backup name is not formatted correctly. It should be similar to “[_1]”.',
            ['aliases-domain.com.gz']
        );
    }
    return;
}

=head2 INSTANCE->_write_config(DOMAIN, FH, PID) [PRIVATE]

Write the user's email forwarder for the domain.

=head3 ARGUMENTS

=over

=item DOMAIN - string

Domain to set the forwarder config to.

=item FH - file handle

Stream of configuration to write for the domain.

=item PID - pid

Background process id to wait on.

=back

=head3 THROWS

=over

=item When the file cannot be opened for writing.

=item When the file cannot be written too.

=back

=cut

sub _write_config {
    my ( $self, $domain, $fh, $pid, $filename ) = @_;

    my $select = IO::Select->new($fh);
    if ( my @ready = $select->can_read(10) ) {
        eval {
            $self->_preserve_config($domain);
            my $config_fh;
            if ( !eof($fh) ) {
                Cpanel::Autodie::open( $config_fh, '>', $self->config_path($domain) );
                while ( !eof($fh) ) {
                    my $line = <$fh>;

                    # TODO: Add line validation DUCK-1826
                    print {$config_fh} $line or die $!;
                }
                Cpanel::Autodie::close($config_fh);
            }
            $self->_commit_config($domain);
            $self->log->done( 'restore_filter', { description => locale()->maketext( 'The system successfully restored the email forwarders from the “[_1]” backup.', $filename ) } );
        };
        if ( my $exception = $@ ) {
            $self->_rollback_config($domain);
            close($fh);
            die $exception;
        }
    }
    else {
        if ( $!{EINTR} ) {
            $self->log->debug(
                'restore_failed',
                {
                    description => locale()->maketext(
                        'A system administrator interrupted the email forwarder restoration.',
                    )
                }
            );
        }
        elsif ( my $exception = $! ) {
            $self->log->error(
                'restore_failed',
                {
                    description => locale()->maketext(
                        'The system failed to restore the email forwarder configuration with the following error: [_1]',
                        $exception
                    )
                }
            );
        }
        return;
    }

    waitpid( $pid, 0 ) if defined $pid;

    close($fh);
    return;
}

=head2 INSTANCE->_preserve_config(DOMAIN) [PRIVATE]

Save a backup of the user's email forwarder configuration so we can roll it back if something fails.

=head3 ARGUMENTS

=over

=item DOMAIN - string

Domain for the configuration.

=back

=cut

sub _preserve_config {
    my ( $self, $domain ) = @_;
    $self->log->debug( 'restore_checkpoint', { description => locale()->maketext( 'Saving the current email forwarder configuration for the “[_1]” domain in case of restore failure.', $domain ) } );

    # We have to copy the contents since we cannot rename the file in /var/aliases due to permissions
    $self->copy_file_if_exists( $self->config_path($domain), $self->config_backup_path($domain) );
    return;
}

=head2 INSTANCE->_rollback_config(DOMAIN) [PRIVATE]

Roll back the user's email forwarder configuration for a domain to what it was before we started.

=head3 ARGUMENTS

=over

=item DOMAIN - string

Domain for the configuration.

=back

=cut

sub _rollback_config {
    my ( $self, $domain ) = @_;
    $self->log->debug(
        'restore_rollback',
        {
            description => locale()->maketext(
                'Recovering the previous email forwarder configuration for the “[_1]” domain.',
                $domain
            )
        }
    );

    # We have to copy the contents since we cannot rename the file in /var/aliases due to permissions
    $self->copy_file_if_exists( $self->config_backup_path($domain), $self->config_path($domain) );
    Cpanel::Autodie::unlink_if_exists( $self->config_backup_path($domain) );
    return;
}

=head2 INSTANCE->_commit_config(DOMAIN) [PRIVATE]

Clean up the backup file for the configuration.

=head3 ARGUMENTS

=over

=item DOMAIN - string

Domain for the configuration.

=back

=cut

sub _commit_config {
    my ( $self, $domain ) = @_;
    $self->log->debug( 'restore_commit', { description => locale()->maketext('Cleaning up the rollback check point.') } );
    Cpanel::Autodie::unlink_if_exists( $self->config_backup_path($domain) );
    return;
}

1;
