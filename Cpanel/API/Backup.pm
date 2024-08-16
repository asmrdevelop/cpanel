package Cpanel::API::Backup;

# cpanel - Cpanel/API/Backup.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                       ();
use Cpanel::AdminBin             ();
use Cpanel::Config::Constants    ();
use Cpanel::Exception            ();
use Cpanel::Form                 ();
use Cpanel::Locale               ();
use Cpanel::SSH::CredentialCheck ();
use Cpanel::Validate::Boolean    ();
use Cpanel::Validate::EmailRFC   ();
use Cpanel::Validate::Integer    ();

use constant MAXIMUM_RESTORE_DB_RUNTIME         => 7200;
use constant MAXIMUM_RESTORE_FILES_RUNTIME      => $Cpanel::Config::Constants::MAX_HOMEDIR_STREAM_TIME;
use constant MAXIMUM_RESTORE_FILTERS_RUNTIME    => 7200;
use constant MAXIMUM_RESTORE_FORWARDERS_RUNTIME => 7200;

=encoding utf-8

=head1 MODULE

C<Cpanel::API::Backup>

=head1 DESCRIPTION

C<Cpanel::API::Backup> provides various API calls related to backup and restore operations.

=head1 FUNCTIONS

=cut

sub list_backups {
    my ( $args, $result ) = @_;

    my @data;

    my $output = Cpanel::AdminBin::adminfetchnocache( 'backup', '', 'LISTDATES', 'storable', '' );

    foreach my $line ( @{$output} ) {
        chomp($line);
        if ( $line =~ m/^ERROR\:(.*)$/ ) {
            $result->raw_error($1);
            return;
        }
        elsif ( $line =~ m/^\d{4}\-\d{2}\-\d{2}$/ ) {
            push( @data, $line );
        }
    }

    my $ocnt = @data;
    $result->metadata( 'cnt', $ocnt );
    $result->data( \@data );
    return 1;
}

sub fullbackup_to_homedir {
    my ( $args, $result ) = @_;
    return _do_fullbackup( $args, $result, dest => 'homedir' );
}

sub fullbackup_to_ftp {
    my ( $args, $result ) = @_;

    my ( $un, $host ) = _get_non_homedir_destination_args($args);

    # ftpput currently does not support empty passwords
    # and we do not recommend this
    my $pw = $args->get_length_required('password') // q<>;

    my $variant = $args->get('variant') // 'active';

    if ( $variant ne 'active' && $variant ne 'passive' ) {
        die "Unrecognized “variant”: “$variant”";
    }

    $variant = q<> if $variant eq 'active';

    my ( $rdir, $port ) = $args->get( 'directory', 'port' );

    $rdir ||= '';    # not required
    $port ||= '';    # not required

    return _do_fullbackup(
        $args,
        $result,
        preflight => sub {
            _verify_ftp_access( 'ruser' => $un, 'rpass' => $pw, 'server' => $host, 'variant' => $variant, 'rdir' => $rdir, 'port' => $port );
        },
        dest   => "${variant}ftp",
        ruser  => $un,
        rpass  => $pw,
        server => $host,
        port   => $port,
        rdir   => $rdir,
    );
}

sub _verify_ftp_access {
    my %opts = @_;
    my ( $un, $pw, $host, $variant, $rdir, $port ) = @opts{qw(ruser rpass server variant rdir port)};

    require Cpanel::SafeRun::Object;

    # If we cannot connect after 60 seconds we need to timeout so we give an error
    my $run = Cpanel::SafeRun::Object->new(
        'program' => '/usr/local/cpanel/bin/ftpput',
        'args'    => [ '', $host, $un, "ftp$variant", $rdir, $port ],
        'stdin'   => $pw,
        timeout   => 60,
    );

    if ( $run->CHILD_ERROR() ) {
        my $msg    = join( q< >, map { $run->$_() // () } qw( stdout stderr ) ) || $run->autopsy();
        my $locale = Cpanel::Locale->get_handle();
        if ( $run->timed_out() ) {
            die $locale->maketext(
                "The system failed to transport the backups via [asis,FTP] because the connection timed out during communication with “[_1]”: [_2]",
                $host, $msg
            );
        }
        else {
            die $locale->maketext( "The system failed to transport the backups via [asis,FTP] due to an error: [_1]", $msg );
        }
    }

    return;
}

sub fullbackup_to_scp_with_password {
    my ( $args, $result ) = @_;

    my $pw = $args->get_length_required('password');

    return _fullbackup_to_scp( $args, $result, $pw );
}

sub fullbackup_to_scp_with_key {
    my ( $args, $result ) = @_;

    my $keyname = $args->get_length_required('key_name');
    my $keypass = $args->get('key_passphrase');

    return _fullbackup_to_scp( $args, $result, undef, $keyname, $keypass );
}

sub _fullbackup_to_scp {
    my ( $args, $result, $pw, $keyname, $keypass ) = @_;

    my ( $un, $host ) = _get_non_homedir_destination_args($args);

    $pw //= q<>;

    my $port = $args->get('port');

    return _do_fullbackup(
        $args,
        $result,
        preflight => sub {
            my $args = {
                'host'                   => $host,
                'port'                   => $port,
                'user'                   => $un,
                'password'               => $pw,
                'root_escalation_method' => 'none',
                'sshkey_name'            => $keyname,
                'sshkey_passphrase'      => $keypass,
            };

            my $metadata = {};

            my $ret = Cpanel::SSH::CredentialCheck::remote_basic_credential_check( $args, $metadata );
            if ( !$metadata->{'result'} ) {
                die $metadata->{'reason'};
            }
        },
        dest              => 'scp',
        ruser             => $un,
        rpass             => $pw,
        server            => $host,
        port              => $port,
        sshkey_name       => $keyname,
        sshkey_passphrase => $keypass,
        rdir              => $args->get('directory'),
    );
}

sub _get_non_homedir_destination_args {
    my ($args) = @_;

    return $args->get_length_required( 'username', 'host' );
}

sub _do_fullbackup {
    my ( $args, $result, %opts ) = @_;

    my $email = $args->get('email');

    my $locale;

    $email = Cpanel::Validate::EmailRFC::normalize($email);

    if ( length $email && !Cpanel::Validate::EmailRFC::is_valid($email) ) {
        $locale ||= Cpanel::Locale->get_handle();
        die $locale->maketext( "The email address “[_1]” is not valid.", $email );
    }

    for my $db_arg ( 'dbbackup', 'dbbackup_mysql' ) {
        if ( my $val = $args->get($db_arg) ) {
            $opts{$db_arg} = $val;
        }
    }

    if ( my $val = $args->get('homedir') ) {
        if ( $val eq 'skip' ) {
            $opts{'skiphomedir'} = 1;
        }
        elsif ( $val ne 'include' ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid value of “[_2]”. Use [list_or_quoted,_3].', [ $val, 'homedir', [ 'skip', 'include' ] ] );
        }
    }

    my $preflight = delete $opts{'preflight'};
    $preflight->() if $preflight;

    my $pid = Cpanel::AdminBin::adminstor(
        'backup',
        'BACKUP',
        {
            %opts,
            'email' => $email,
        }
    );

    if ( $Cpanel::CPERROR{$Cpanel::context} ) {
        die $Cpanel::CPERROR{$Cpanel::context};
    }

    $result->data( { pid => $pid } );

    return 1;
}

=head2 restore_databases()

=head3 ARGUMENTS

=over

=item backup - string [Multiple Allowed]

Optional. Path to a file on the server's file system. Only provide this when calling from the command line.

Supports files of the following types:

=over

=item .sql

Plain text sql dump files.

=item .sql.gz

Gzipped sql dump files.

=back

When file uploads are provided via webforms, do not pass this parameter.

=item verbose - Boolean

When 1, the output will include additional information logged via debug() calls.

=item timeout - number

Maximum number of seconds to run the restore before giving up. Defaults to 7200 seconds (2 hours). To disable the timeout, set to 0.

=back

=head3 THROWS

=over

=item When the files requested cannot be located or accessed.

=item When any .gz files are damaged or corrupt.

=item When any .gz file contains a virus.

=item When expanding the .gz file causes the users account to exceed its quota.

=item When the restoration of any backup fails for any reason.

=item When the uploads can not be persisted in the temporary directory.

=back

=head3 EXAMPLES

=head4 Command line usage for one upload

Upload your backup archive to /home/cpuser.

Then run the uapi call:

    uapi --user=cpuser --output=jsonpretty Backup restore_databases backup=/home/cpuser/cpuser_db1.sql.gz

The returned data will contain a structure similar to the JSON below:

    {
       "func" : "restore_databases",
       "apiversion" : 3,
       "result" : {
          "errors" : null,
          "metadata" : {},
          "data" : {
             "log_path" : "/home/cpuser/.cpanel/restoredb/logs/2019-08-05T10:22:22.1.log",
             "log_id" : "2019-08-05T10:22:22.1"
          },
          "messages" : [
             "Determined database name from SQL script.",
             "The system will attempt to restore from the file cpuser_db1.sql.gz to the database: cpuser_db1",
             "Created the temp database user cpuser_wdiyj0te since it did not have the cPanel account credentials",
             "Linked the temp database user cpuser_wdiyj0te to the database cpuser_wp",
             "Remove the temp database user cpuser_wdiyj0te",
             "The system successfully restored the database 'cpuser_db1' from the backup file 'cpuser_db1.sql.gz'."
          ],
          "status" : 1,
          "warnings" : null
       },
       "module" : "Backup"
    }

=head4 Command line usage for multiple uploads

Upload your backup archives to /home/cpuser.

Then run the uapi call:

    uapi --user=cpuser --output=jsonpretty Backup restore_databases backup-1=/home/cpuser/cpuser_db1.sql.gz backup-2=/home/cpuser/cpuser_db2.sql.gz

The returned data will contain a structure similar to the JSON below:

    {
           "func" : "restore_databases",
           "apiversion" : 3,
           "result" : {
              "errors" : null,
              "metadata" : {},
              "data" : {
                 "log_path" : "/home/cpuser/.cpanel/restoredb/logs/2019-08-05T10:22:22.1.log",
                 "log_id" : "2019-08-05T10:22:22.1"
              },
              "messages" : [
                 "Determined database name from SQL script.",
                 "The system will attempt to restore from the file cpuser_db1.sql.gz to the database: cpuser_db1",
                 "Created the temp database user cpuser_wdiyj0te since it did not have the cPanel account credentials",
                 "Linked the temp database user cpuser_wdiyj0te to the database cpuser_wp",
                 "Remove the temp database user cpuser_wdiyj0te",
                 "The system successfully restored the database 'cpuser_db1' from the backup file 'cpuser_db1.sql.gz'."
                 "Determined database name from SQL script.",
                 "The system will attempt to restore from the file cpuser_db2.sql.gz to the database: cpuser_db2",
                 "Created the temp database user cpuser_wdiyj0te since it did not have the cPanel account credentials",
                 "Linked the temp database user cpuser_wdiyj0te to the database cpuser_wp",
                 "Remove the temp database user cpuser_wdiyj0te",
                 "The system successfully restored the database 'cpuser_db2' from the backup file 'cpuser_db2.sql.gz'."
              ],
              "status" : 1,
              "warnings" : null
           },
           "module" : "Backup"
        }

=head4 Template Toolkit

Starting with a webform like:

  <form href="submit.html.tt">
    Enter the file: <input type="file" name="file-1">
    <button type="submit">Restore</button>
  </form>

We have the submit.html.tt page:

  [%
    SET resp = execute('Backup', 'restore_databases', {});
    IF resp.status == 1;
   -%]
    Restore was successful.
   [% ELSE %]
    Failed to restore the database with [% resp.errors.1 %]
   [% END
  %]

=cut

sub restore_databases {
    my ( $args, $result ) = @_;

    _assert_no_preprocessing_form_errors();

    my (@files) = $args->get_multiple('backup');
    die Cpanel::Exception::create(
        'InvalidParameter',
        'You must provide one or more “[_1]” parameters when calling this method without file uploads.',
        ['backup'],
    ) if !Cpanel::Form::has_uploaded_files() && !@files;

    my $verbose = $args->get('verbose') // 0;
    Cpanel::Validate::Boolean::validate_or_die($verbose);

    my $timeout = $args->get('timeout');
    _validate_timeout( $timeout, MAXIMUM_RESTORE_DB_RUNTIME );

    require Cpanel::Backup::Restore::Database;
    my $log = Cpanel::Backup::Restore::Database::restore_databases( @files ? \@files : undef, timeout => $timeout, verbose => $verbose );

    $result->data(
        {
            log_path => $log->path(),
            log_id   => $log->id(),
        }
    );

    # NOTE: We are doing this for now since this is synchronous.
    # Later when we make this a background process we will not return this
    # information here, but through an SSE connection.
    return _expand_log_messages_into_results( $log, $result, $verbose );
}

=head2 restore_files()

=head3 ARGUMENTS

=over

=item backup - string

Optional. The archive from which to restore. If you do not provided this parameter, you must have called this
API with a FORM upload. This parameter may be provided multiple times to restore multiple archives. Archives are
all restored to the same directory and are applied in the order submitted.

=item directory - string

Optional. The full path of the directory to which to restore. By default, the function restores to the user's home directory.

=item verbose - Boolean

Optional. False by default. When true, the output log will include entries for each file extracted from the archive.

=item timeout - number

Optional. Maximum number of seconds to run the restore before giving up. Defaults to 7200 seconds (2 hours). To disable the timeout, set to 0.

=back

=head3 THROWS

=over

=item When neither a backup or a FORM upload is provided.

=item When the directory parameter is passed but is an empty string.

=item When the uploads can not be persisted in the temporary directory.

=back

=head3 EXAMPLES

=head4 Command line usage to restore the home folder:

    uapi --user=cpuser Backup restore_files backup=/home/cpuser/backup-cpuser.tld-9-10-2019_1.tar.gz

The returned data will contain a structure similar to the JSON below:

    {
       "apiversion" : 3,
       "func" : "restore_files",
       "module" : "Backup",
       "result" : {
          "data" : {
             "log_id" : "2019-09-11T18:30:49Z.1",
             "log_path" : "/home/cpuser/.cpanel/logs/restorefiles/2019-09-11T18:30:49Z.1.log"
          },
          "status" : 1,
          "errors" : null,
          "messages" : [
             "Created the restore directory “/home/cpuser/point2”.",
             "No virus detected in upload “backup-cpuser.tld-9-10-2019_1.tar.gz”.",
             "The system is extracting the archive “/home/cpuser/backup-cpuser.tld-9-10-2019_1.tar.gz”.",
             "The system successfully restored the directory “/home/cpuser/point2” from the backup file “backup-cpuser.tld-9-10-2019_1.tar.gz”."
          ],
          "warnings" : null,
          "metadata" : {}
       }
    }

=head4 Command line usage to restore the archive to a specific folder:

    uapi --user=cpuser Backup restore_files backup=/home/cpuser/backup-cpuser.tld-9-10-2019_1.tar.gz directory=/home/cpuser/test

The returned data will contain a structure similar to the JSON below:

    {
       "apiversion" : 3,
       "func" : "restore_files",
       "module" : "Backup",
       "result" : {
          "data" : {
             "log_id" : "2019-09-11T18:30:49Z.1",
             "log_path" : "/home/cpuser/.cpanel/logs/restorefiles/2019-09-11T18:30:49Z.1.log"
          },
          "status" : 1,
          "errors" : null,
          "messages" : [
             "Created the restore directory “/home/cpuser/point2”.",
             "No virus detected in upload “backup-cpuser.tld-9-10-2019_1.tar.gz”.",
             "The system is extracting the archive “/home/cpuser/backup-cpuser.tld-9-10-2019_1.tar.gz”.",
             "The system successfully restored the directory “/home/cpuser/point2” from the backup file “backup-filerestore.tld-9-10-2019_1.tar.gz”."
          ],
          "warnings" : null,
          "metadata" : {}
       }
    }

=head4 Template Toolkit

Starting with a webform like:

  <form href="submit.html.tt">
    Enter the file: <input type="file" name="file-1">
    <button type="submit">Restore</button>
  </form>

We have the submit.html.tt page:

  [%
    SET resp = execute('Backup', 'restore_files', {});
    IF resp.status == 1;
       # Success
       SET len = resp.messages.size();
       SET last = len - 1;
    %]
    [% resp.messages.$last %]
   [% ELSE %]
    Failed to restore the database with [% resp.errors.1 %]
   [% END
  %]

=cut

sub restore_files {
    my ( $args, $result ) = @_;

    _assert_no_preprocessing_form_errors();

    my (@files) = $args->get_multiple('backup');
    die Cpanel::Exception::create(
        'InvalidParameter',
        'You must provide one or more “[_1]” parameters when calling this method without file uploads.',
        ['backup'],
    ) if !Cpanel::Form::has_uploaded_files() && !( scalar @files && scalar grep { defined $_ && $_ ne "" } @files );

    my $directory = $args->get('directory');
    my $verbose   = $args->get('verbose') // 0;
    Cpanel::Validate::Boolean::validate_or_die( $verbose, 'verbose' );

    my $timeout = $args->get('timeout');
    _validate_timeout( $timeout, MAXIMUM_RESTORE_FILES_RUNTIME );

    require Cpanel::Backup::Restore::Files;
    my $manager = Cpanel::Backup::Restore::Files->new( timeout => $timeout, verbose => $verbose );
    my $log     = $manager->restore( @files ? \@files : undef, directory => $directory );

    $result->data(
        {
            log_path => $log->path(),
            log_id   => $log->id(),
        }
    );

    # NOTE: We are doing this for now since this is synchronous.
    # Later when we make this a background process we will not return this
    # information here, but through an SSE connection.
    return _expand_log_messages_into_results( $log, $result, $verbose );
}

=head2 restore_email_filters()

=head3 ARGUMENTS

=over

=item backup - string [Multiple Allowed]

Optional. Path to a file on the server's file system. Only provide this when calling from the command line.

B<NOTE:> When file uploads are provided via webforms, do not pass this parameter.

Supports files of the following types:

=over

=item * filter_info.{user}.yaml.gz - compressed YAML filter configuration for an account.

=item * filter_info.{user}.yaml - non-compressed YAML filter configuration for an account

=back

For the file names, observe the following:

=over

=item The {user} must match the current cpanel users username.

=back

=item verbose - Boolean

When 1, the output will include additional information logged via debug() calls.

=item timeout - number

Maximum number of seconds to run the restore before giving up. Defaults to 7200 seconds (2 hours). To disable the timeout, set to 0.

=back

=head3 THROWS

=over

=item When the files requested cannot be located or accessed.

=item When any .gz files are damaged or corrupt.

=item When any .gz file contains a virus.

=item When expanding the .gz file causes the user's account to exceed its quota.

=item When the restoration of the filters fails for any reason.

=item When the uploads can not be persisted in the temporary directory.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    uapi --user=cpuser --output=jsonpretty Backup restore_email_filters backup=filter_info.cpuser.yaml.gz

The returned data will contain a structure similar to the JSON below:

    "result" : {
      "messages" : [
         "No virus detected in upload “filter_info.cpuser.yaml.gz”.",
         "The system is extracting the archive “/home/cpuser/filter_info.cpuser.yaml.gz”.",
         "The system successfully restored the email filters from the “filter_info.cpuser.yaml.gz” backup."
      ],
      "metadata" : {},
      "data" : {
         "log_path" : "/home/cpuser/.cpanel/logs/restore-email-filters/2019-10-03T18:44:03Z.1.log",
         "log_id" : "2019-10-03T18:44:03Z.1"
      },
      "status" : 1,
      "warnings" : null,
      "errors" : null
   }


=head4 Template Toolkit

Starting with a webform like:

  <form href="submit.html.tt">
    Enter the file: <input type="file" name="file-1">
    <button type="submit">Restore Filters</button>
  </form>

We have the submit.html.tt page:

  [%
    SET resp = execute('Backup', 'restore_email_filters', {});
    IF resp.status == 1;
       # Success
       SET len = resp.messages.size();
       SET last = len - 1;
    %]
    [% resp.messages.$last %]
   [% ELSE %]
    Failed to restore the accounts email filters with [% resp.errors.1 %]
   [% END
  %]

=cut

sub restore_email_filters {
    my ( $args, $result ) = @_;

    _assert_no_preprocessing_form_errors();

    my (@files) = $args->get_multiple('backup');
    die Cpanel::Exception::create(
        'InvalidParameter',
        'You must provide one or more “[_1]” parameters when calling this method without file uploads.',
        ['backup'],
    ) if !Cpanel::Form::has_uploaded_files() && !@files;

    my $verbose = $args->get('verbose') // 0;
    Cpanel::Validate::Boolean::validate_or_die($verbose);

    my $timeout = $args->get('timeout');
    _validate_timeout( $timeout, MAXIMUM_RESTORE_FILTERS_RUNTIME );

    require Cpanel::Backup::Restore::EmailFilters;
    my $manager = Cpanel::Backup::Restore::EmailFilters->new( timeout => $timeout, verbose => $verbose );
    my $log     = $manager->restore( @files ? \@files : undef );

    $result->data(
        {
            log_path => $log->path(),
            log_id   => $log->id(),
        }
    );

    # NOTE: We are doing this for now since this is synchronous.
    # Later when we make this a background process we will not return this
    # information here, but through an SSE connection.
    return _expand_log_messages_into_results( $log, $result, $verbose );
}

=head2 restore_email_forwarders()

=head3 ARGUMENTS

=over

=item backup - string [Multiple Allowed]

Optional. Path to a file on the server's file system. Only provide this when calling from the command line.

B<NOTE:> When file uploads are provided via webforms, do not pass this parameter.

The system supports the following file formats:

=over

=item * aliases-{domain}.gz - compressed email forwarder configuration for a specific domain.

=item * aliases-{domain} - email forwarder configuration for a specific domain.

=back

For these, observe the following:

=over

=item The {domain} indicates the fully qualified domain to restore the forwarders to and must be owned by the current user.

=back

=item verbose - Boolean

When 1, the output will include additional information logged via debug() calls.

=item timeout - number

Maximum number of seconds to run the restore before giving up. Defaults to 7200 seconds (2 hours). To disable the timeout, set to 0.

=back

=head3 THROWS

=over

=item When the files requested cannot be located or accessed.

=item When any .gz files are damaged or corrupt.

=item When any .gz file contains a virus.

=item When expanding the .gz file causes the user's account to exceed its quota.

=item When the restoration of the email forwarders fail for any reason.

=item When the uploads can not be persisted in the temporary directory.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    uapi --user=cpuser --output=jsonpretty Backup restore_email_forwarders backup=aliases-domain.com.gz

The returned data will contain a structure similar to the JSON below:

    "result" : {
      "status" : 1,
      "messages" : [
         "No virus detected in upload “aliases-domain.com.gz”.",
         "The system is extracting the “/home/cpuser/aliases-domain.com.gz” archive.",
         "The system successfully restored the email forwarders from the “aliases-domain.com.gz” backup."
      ],
      "errors" : null,
      "metadata" : {},
      "data" : {
         "log_id" : "2019-10-04T20:27:25Z.1",
         "log_path" : "/home/cpuser/.cpanel/logs/restore-email-forwarders/2019-10-04T20:27:25Z.1.log"
      },
      "warnings" : null
    },

=head4 Template Toolkit

    Starting with a webform like:

      <form href="submit.html.tt">
        Enter the file: <input type="file" name="file-1">
        <button type="submit">Restore Forwarders</button>
      </form>

    We have the submit.html.tt page:

      [%
        SET resp = execute('Backup', 'restore_email_forwarders', {});
        IF resp.status == 1;
           # Success
           SET len = resp.messages.size();
           SET last = len - 1;
        %]
        [% resp.messages.$last %]
       [% ELSE %]
        Failed to restore the accounts email forwarders with [% resp.errors.1 %]
       [% END
      %]

=cut

sub restore_email_forwarders {
    my ( $args, $result ) = @_;

    _assert_no_preprocessing_form_errors();

    my (@files) = $args->get_multiple('backup');
    die Cpanel::Exception::create(
        'InvalidParameter',
        'You must provide one or more “[_1]” parameters when calling this method without file uploads.',
        ['backup'],
    ) if !Cpanel::Form::has_uploaded_files() && !@files;

    my $verbose = $args->get('verbose') // 0;
    Cpanel::Validate::Boolean::validate_or_die($verbose);

    my $timeout = $args->get('timeout');
    _validate_timeout( $timeout, MAXIMUM_RESTORE_FORWARDERS_RUNTIME );

    require Cpanel::Backup::Restore::EmailForwarders;
    my $manager = Cpanel::Backup::Restore::EmailForwarders->new( timeout => $timeout, verbose => $verbose );
    my $log     = $manager->restore( @files ? \@files : undef );

    $result->data(
        {
            log_path => $log->path(),
            log_id   => $log->id(),
        }
    );

    # NOTE: We are doing this for now since this is synchronous.
    # Later when we make this a background process we will not return this
    # information here, but through an SSE connection.
    return _expand_log_messages_into_results( $log, $result, $verbose );
}

=head2 _validate_timeout(TIMEOUT, MAX)

Validate the timeout if its defined.

=head3 ARGUMENTS

=over

=item TIMEOUT - number

=item MAX - number

=back

=head3 THROWS

When the timeout is not an integer and out of the range allowed.

=cut

sub _validate_timeout {
    my ( $timeout, $max ) = @_;
    return if !defined $timeout;

    Cpanel::Validate::Integer::unsigned_and_less_than( $timeout, MAXIMUM_RESTORE_DB_RUNTIME );
    die Cpanel::Exception::create(
        'InvalidParameter',
        'The “[_1]” parameter must be an integer between 0 and “[_2]” inclusive.', [ 'timeout', $max ],
    ) if $timeout < 0;

    return;
}

=head2 _expand_log_messages_into_results(LOG, RESULT, VERBOSE) [PRIVATE]

Unpackage the log information into the results object.

=head3 ARGUMENTS

=over

=item LOG - Cpanel::Background::Log

=item RESULT - Cpanel::Result

=item VERBOSE - Boolean

=back

=head3 RETURNS

1 if the log indicated a success, 0 if it indicated a failure.

=cut

sub _expand_log_messages_into_results {
    my ( $log, $result, $verbose ) = @_;

    my $data = $log->deserialize();
    if ( my @errors = grep { $_->{type} eq 'error' } @$data ) {
        foreach my $error (@errors) {
            $result->raw_error( $error->{data}{description} );
        }
        return 0;
    }

    if ( my @warnings = grep { $_->{type} eq 'warn' } @$data ) {
        foreach my $warning (@warnings) {
            $result->raw_warning( $warning->{data}{description} );
        }
    }

    if ( my @messages = grep { $_->{type} eq 'info' || ( $verbose && $_->{type} eq 'debug' ) || $_->{type} eq 'done' } @$data ) {
        foreach my $message (@messages) {
            $result->raw_message( $message->{data}{description} );
        }
    }
    return 1;
}

=head2 _assert_no_preprocessing_form_errors()

Check if the form has any error that happened during the parsing. This
is most likely errors related to uploaded files failing to be written to
the temporary location due to disk space or quota issues.

=head3 THROWS

When there are errors during form processing. It only throws the first
error it finds.

=cut

sub _assert_no_preprocessing_form_errors {
    if ( my @errors = Cpanel::Form::get_errors() ) {
        die Cpanel::Exception->create_raw( $errors[0] );
    }
}

# NOTE: These checks are also used in Cpanel::Backups to apply the same
#       restrictions to the equivalent deprecated cPAPI1 methods.
our %API = (
    _needs_feature           => "backup",
    list_backups             => { allow_demo => 1 },
    restore_databases        => { needs_role => 'MySQLClient' },
    restore_email_filters    => { needs_role => 'MailReceive' },
    restore_email_forwarders => { needs_role => 'MailReceive' },
    restore_files            => { needs_role => 'FileStorage' },
);

1;
