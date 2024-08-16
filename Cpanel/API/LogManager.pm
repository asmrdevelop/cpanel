package Cpanel::API::LogManager;

# cpanel - Cpanel/API/LogManager.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LogManager ();
use Cpanel::Exception  ();

=head1 MODULE

C<Cpanel::API::LogManager>

=head1 DESCRIPTION

C<Cpanel::API::LogManager> provides UAPI calls used to control how log archives
are created and managed. Also provides API calls to retrieve the list of
available log archives.

Log archive configuration is stored in the users ./.cpanel-logs file.

Log archives are stored in the users ./logs folder.

=head1 FUNCTIONS

=cut

my $allow_demo = { allow_demo => 1 };
my $no_demo    = { allow_demo => 0 };

our %API = (

    _needs_role    => 'WebServer',
    _needs_feature => 'rawlog',
    get_settings   => $allow_demo,
    set_settings   => $no_demo,
    list_archives  => $allow_demo,
);

=head2 get_settings()

Get the log archive setting for the current user.

=head3 RETURNS

Hash with the following properties:

=over

=item archive_logs - Boolean

If 1, the system archives log files to your home directory after
the system processes statistics. The system currently processes
logs every 24 hours. This defaults to the value of the
C<default_archive-logs> property in the cpanel configuration
file. If 0, does not archive logs.

=item prune_archive - Boolean

If 1, the system removes the previous month's archived logs from
your home directory at the end of each month. This defaults to the
value of the C<default_remove-old-archived-logs> property in the
cpanel configuration file. If 0, does not remove archived logs.

=back

=head3 THROWS

=over

=item When there is trouble reading the underlying ~/.cpanel-logs file.

=item When there is trouble loading the cpconf file.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    uapi --user=cpuser --output=jsonpretty LogManager get_settings

The returned data will contain a structure similar to the JSON below:

    "data" : {
       "archive_logs" : 1,
       "prune_archive" : 1
    }

=head4 Template Toolkit

    [%-
    SET result = execute('LogManager', 'get_settings', {});
    IF result.status
    -%]
    Archive Logs:   [% result.data.archive_logs ? 'YES' : 'NO' %]
    Purge Archived: [% result.data.prune_archive ? 'YES' : 'NO' %]
    [%- END -%]

=cut

sub get_settings {
    my ( $args, $result ) = @_;

    $result->data( Cpanel::LogManager::list_settings() );

    return 1;
}

=head2 list_archives()

Gets a list of the archives available for the current user.

=head3 RETURNS

Array of hashes - Each one has the following properties:

=over

=item file - string

name of the archive file in /home/{user}/logs.

=item path - string

full path to the archive on disk

=item mtime - UNIX Timestamp

The time the archive was last modified.

=back

=head3 THROWS

=over

=item When the log directory exists but can not be read.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    uapi --user=cpuser --output=jsonpretty LogManager list_archives

The returned data will contain a structure similar to the JSON below:

    "data" : [
        {
            "mtime" : 1557835866,
            "path" : "/home/cpuser/logs/domain.com-May-2019.gz",
            "file" : "domain.com-May-2019.gz"
        },
        {
            "path" : "/home/cpuser/logs/domain.com-Apr-2019.gz",
            "mtime" : 1556168400,
            "file" : "domain.com-Apr-2019.gz"
        },
        {
            "file" : "domain.com-Mar-2019.gz",
            "mtime" : 1553490000,
            "path" : "/home/cpuser/logs/domain.com-Mar-2019.gz"
        }
    ]

=head4 Template Toolkit

    [%
    SET result = execute('module', 'list_archives', {});
    IF result.status;
        FOREACH log IN result.data %]
            File: [% log.file %]
            Date: [% locale.datetime(log.mtime,'datetime_format_full')%]
    [%  END;
    END
    %]

=cut

sub list_archives {
    my ( $args, $result ) = @_;

    $result->data( Cpanel::LogManager::list_logs() );

    return 1;
}

=head2 set_settings()

Save the log archive settings for the current user.

=head3 ARGUMENTS

=over

=item archive_logs - Boolean

Optional, if 1, the system will archives log files to your home directory after
the system processes statistics. If 0, the system does not archive logs. When not
provided, will default to its current saved value or the default in tweak settings.

=item prune_archive - Boolean

Optional, if 1, the system will remove the previous months archived logs from
your home directory at the end of each month. If 0, the system does not remove
archived logs. When not provided, will default to its current saved value or the
fault in tweak settings.

=back

=head3 THROWS

=over

=item When you do not pass any arguments

=item When you pass an argument value that is not valid for the field.

=back

=head3 EXAMPLES

=head4 Command line usage for today

    uapi --user=cpuser --output=jsonpretty LogManager set_settings archive_logs=1 prune_archive=1

The call does not return data.

    "data" : null

=head4 Template Toolkit

    [%
    SET result = execute('module', 'set_settings', {
        archive_logs  => 1,
        prune_archive => 1,
    });
    IF result.status %]
    Saved successfully.
    [% ELSE %]
    ERROR: [% result.errors.0 %]
    [% END %]

=cut

sub set_settings {
    my ( $args, $result ) = @_;

    my $archive_logs  = $args->get('archive_logs');
    my $prune_archive = $args->get('prune_archive');

    if ( !defined($archive_logs) && !defined($prune_archive) ) {
        die Cpanel::Exception::create( 'MissingParameters', 'You must pass one or more of [list_or,_1].', [ [qw(archive_logs prune_archive)] ] );
    }

    require Cpanel::Validate::Boolean;
    Cpanel::Validate::Boolean::validate_or_die( $archive_logs,  'archive_logs' )  if defined($archive_logs);
    Cpanel::Validate::Boolean::validate_or_die( $prune_archive, 'prune_archive' ) if defined($prune_archive);

    Cpanel::LogManager::save_settings( $archive_logs, $prune_archive );
    return 1;
}

1;
