package Whostmgr::API::1::RemoteMySQL;

# cpanel - Whostmgr/API/1/RemoteMySQL.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Try::Tiny;
use Capture::Tiny       ();
use Cpanel::DIp::MainIP ();

use Cpanel::Sys::Hostname                           ();
use Cpanel::Rand::Get                               ();
use Cpanel::Locale                                  ();
use Cpanel::CloseFDs                                ();
use Cpanel::Exception                               ();
use Cpanel::MysqlUtils::MyCnf::Basic                ();
use Cpanel::MysqlUtils::Quote                       ();
use Cpanel::ForkAsync                               ();
use Cpanel::MysqlUtils::Version                     ();
use Cpanel::Update::Blocker::Constants::MySQL       ();
use Cpanel::MysqlUtils::RemoteMySQL::ActivationJob  ();
use Cpanel::MysqlUtils::RemoteMySQL::ProfileManager ();
use Whostmgr::API::1::Utils                         ();

use constant NEEDS_ROLE => {
    remote_mysql_create_profile              => undef,
    remote_mysql_create_profile_via_ssh      => undef,
    remote_mysql_read_profile                => undef,
    remote_mysql_read_profiles               => undef,
    remote_mysql_update_profile              => undef,
    remote_mysql_delete_profile              => undef,
    remote_mysql_validate_profile            => undef,
    remote_mysql_initiate_profile_activation => undef,
    remote_mysql_monitor_profile_activation  => undef
};

=head1 NAME

Whostmgr::API::1::RemoteMySQL - API calls to manage Remote MySQL profiles.

=head1 SYNOPSIS

    use Whostmgr::API::1::RemoteMySQL ();
    Whostmgr::API::1::RemoteMySQL::remote_mysql_create_profile(
        {
            'name'       => 'new mysql server',
            'mysql_user' => 'user',
            'mysql_pass' => 'pass',
            'mysql_port' => 1234,
            'mysql_host' => '1.2.3.4',
        },
        $metadata
    ) or die "something went wrong";

=cut

my $locale;

=head1 Methods

=over 8

=item B<remote_mysql_create_profile>

Creates a new Remote MySQL profile.

B<Input>: Takes two hashrefs:

    * First hashref must contain details about the new profile to create.
      The following information is required:

            name       - Name of the profile to be saved.
            mysql_host - The MySQL server IP or hostname.
            mysql_user - The MySQL username.
            mysql_pass - The MySQL password.
            mysql_port - The MySQL port number.

      Optionally you can specify 'setup_via' to track how the profile was generated and
      'cpcloud' to signal this is a cPanel Cloud service deployment.

    * Second hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the newly created profile on success.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        "profile_details" => {
            "mysql_port" => "3306",
            "setup_via" => "Unspecified",
            "mysql_pass" => "pass",
            "mysql_user" => "root",
            "mysql_host" => "1.2.3.4"
            "cpcloud"    => 0,
        },
        "profile_saved" => "test"
    }

=cut

sub remote_mysql_create_profile {
    my ( $args, $metadata ) = @_;
    $args->{'setup_via'} //= 'User provided database credentials';
    return _create_or_update_profile( $args, $metadata );
}

=item B<remote_mysql_create_profile_via_ssh>

Generates new Remote MySQL profile by logging into the specified server via SSH,
and assigning the necessary MySQL priviliges.

B<Input>: Takes two hashrefs:

    * First hashref must contain details about how to login to remote server.
      The following keys should be present:

        'user'                   - 'ssh_user',
        'password'               - 'ssh_pass',
        'root_password'          - 'root_pass',
        'root_escalation_method' - 'escalation_method',    #sudo/su
        'sshkey_name'            - 'key_name',
        'sshkey_passphrase'      - 'key_passphrase',
        'host'                   - 'hostname',
        'port'                   - 'ssh_port',

    * Optionally add a cpcloud key to signal if this is a cPanel Cloud service deployment.

        'cpcloud'                - '1|0' # defaults to false

    * Second hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the newly created profile on success.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        "profile_details" => {
            "mysql_port" => "3306",
            "setup_via" => "Unspecified",
            "mysql_pass" => "pass",
            "mysql_user" => "root",
            "mysql_host" => "1.2.3.4",
            "cpcloud"     => 0
        },
        "profile_saved" => "test"
    }

=cut

sub remote_mysql_create_profile_via_ssh {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my ( $profile_name, $remote_mysql_pass, $remote_mysql_port, $is_cpcloud );
    try {
        $profile_name = delete $args->{'name'} || die Cpanel::Exception::create( 'MissingParameter', 'Missing parameter: [_1]', ['name'] );

        die Cpanel::Exception::create( 'MissingParameter', 'Missing parameter: [_1]', ['host'] ) if !length $args->{'host'};

        # Case 111589, prevent remote mysql setup to local machine
        die Cpanel::Exception::create( 'RemoteSSHError', 'The specified [asis,hostname], [_1], appears to point to [asis,localhost].', [ $args->{'host'} ] )
          if Cpanel::MysqlUtils::MyCnf::Basic::is_local_mysql( $args->{'host'} );

        $args->{'scriptdir'} = '/root';

        $is_cpcloud = $args->{'cpcloud'} ? 1 : 0;

        require Whostmgr::Remote;

        # Whostmgr::Remote is very noisy - and prints to stdout directly.
        # So we supress that output with Capture::Tiny
        #
        # TODO: Possible that the supressed output has some use details?
        # should we think about passing that 'raw' text back to the user on failures?
        Capture::Tiny::capture(
            sub {
                my $ssh_obj = Whostmgr::Remote->new($args);

                ( $remote_mysql_pass, $remote_mysql_port ) = _get_remote_mysql_pass_and_port($ssh_obj);
                my $script_path = _generate_remote_script($remote_mysql_pass);

                die Cpanel::Exception::create( 'RemoteSSHError', 'Failed to copy the database setup script to the remote server.' )
                  if !_copy_script_to_remote( $ssh_obj, $script_path );

                die Cpanel::Exception::create( 'RemoteSSHError', 'Failed to run the database setup script on the remote server.' )
                  if !_run_script_on_remote( $ssh_obj, $script_path );

                unlink($script_path);
            }
        );
    }
    catch {
        _handle_failure( $metadata, { 'action' => 'create', 'exception' => $_ } );
    };
    return if !$metadata->{'result'};

    return _create_or_update_profile(
        {
            'name'       => $profile_name,
            'mysql_host' => $args->{'host'},
            'mysql_pass' => $remote_mysql_pass,
            'mysql_user' => 'root',
            'mysql_port' => $remote_mysql_port,
            'setup_via'  => 'Profile created via SSH',
            'cpcloud'    => $is_cpcloud,
        },
        $metadata
    );
}

=item B<remote_mysql_read_profile>

Reads details for the specified Remote MySQL profile.

B<Input>: Takes two hashrefs:

    * First hashref must contain details about the profile to read. This hash must contain:

            name - The name of the MySQL profile to read.

    * Second hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the profile on success.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        "profile_details" => {
            "mysql_port" => "3306",
            "setup_via" => "Unspecified",
            "mysql_pass" => "pass",
            "mysql_user" => "root",
            "mysql_host" => "1.2.3.4",
            "cpcloud"    => 0
        },
        "profile_name" => "test"
    }

=cut

sub remote_mysql_read_profile {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my ( $profile_name, $profile_hr );
    try {
        $profile_name = $args->{'name'} || die Cpanel::Exception::create( 'MissingParameter', 'Missing parameter: [_1]', ['name'] );
        my $saved_profiles_hr = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } )->read_profiles();
        $profile_hr = $saved_profiles_hr->{$profile_name} || die Cpanel::Exception::create( 'RecordNotFound', 'No profile named “[_1]” found on the system.', [$profile_name] );
    }
    catch {
        _handle_failure( $metadata, { 'action' => 'read', 'exception' => $_ } );
    };
    return if !$metadata->{'result'};

    return { 'profile_name' => $profile_name, 'profile_details' => $profile_hr };
}

=item B<remote_mysql_read_profiles>

Reads details for all the Remote MySQL profiles on the server.

B<Input>: Takes a single hashref as an argument:

    * A hash reference to the metadata.

B<Output>: Returns a hashref containing details about the profiles on success.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        "$profile_name" => {
            "mysql_port" => "3306",
            "setup_via" => "Unspecified",
            "mysql_pass" => "pass",
            "mysql_user" => "root",
            "mysql_host" => "127.0.0.1",
            "is_localhost_profile" => 1,
            "mysql_version_is_supported" => 0,
            "cpcloud" => 0
        },
        "$profile_name_2" => {
            "mysql_port" => "3306",
            "setup_via" => "Unspecified",
            "mysql_pass" => "pass",
            "mysql_user" => "root",
            "mysql_host" => "2.3.4.5",
            "is_localhost_profile" => 0,
            "cpcloud" => 0
        },
    }

=cut

sub remote_mysql_read_profiles {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my $profiles_hr;
    try {
        $profiles_hr = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } )->read_profiles();

        my $local_version = undef;
        try {
            $local_version = Cpanel::MysqlUtils::Version::current_mysql_version('localhost')->{'short'};
        };

        my $min_version  = Cpanel::Update::Blocker::Constants::MySQL::MINIMUM_RECOMMENDED_MYSQL_RELEASE();
        my $is_supported = ( defined $local_version ? Cpanel::MysqlUtils::Version::is_at_least( $local_version, $min_version ) : undef );

        foreach my $profile ( keys %{$profiles_hr} ) {
            if ( Cpanel::MysqlUtils::MyCnf::Basic::is_local_mysql( $profiles_hr->{$profile}->{'mysql_host'} ) ) {
                $profiles_hr->{$profile}->{'is_localhost_profile'}       = 1;
                $profiles_hr->{$profile}->{'mysql_version_is_supported'} = $is_supported;
            }
            else {
                $profiles_hr->{$profile}->{'is_localhost_profile'} = 0;
            }
        }
    }
    catch {
        _handle_failure( $metadata, { 'action' => 'read', 'exception' => $_ } );
    };

    return if !$metadata->{'result'};

    return $profiles_hr;
}

=item B<remote_mysql_update_profile>

Updates the specified Remote MySQL profile.

B<Input>: Takes two hashrefs:

    * First hashref must contain details about the profile to update. The following information is required:

            name       - Name of the profile to be saved.

      Additionally, one or more of the following values to update:

            mysql_host - The MySQL server IP or hostname.
            mysql_user - The MySQL username.
            mysql_pass - The MySQL password.
            mysql_port - The MySQL port number.
            cpcloud    - Is this profile a cPanel Cloud deployment.

      Optionally you can specify 'setup_via' to track how the profile was generated.
    * Second hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the newly created profile on success.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        "profile_details" => {
            "mysql_port" => "3306",
            "setup_via" => "Unspecified",
            "mysql_pass" => "pass",
            "mysql_user" => "root",
            "mysql_host" => "1.2.3.4",
            "cpcloud"    => 0
        },
        "profile_saved" => "test"
    }

=cut

sub remote_mysql_update_profile {
    my ( $args, $metadata ) = @_;
    return _create_or_update_profile( $args, $metadata, { 'overwrite' => 1 } );
}

=item B<remote_mysql_delete_profile>

Deletes the specified Remote MySQL profile.

B<Input>: Takes two hashrefs:

    * First hashref must contain details about the profile to delete. This hash must contain:

            name - The name of the MySQL profile to delete.

    * Second hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the profile on success.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        "profile_details" => {
            "mysql_port" => "3306",
            "setup_via" => "Unspecified",
            "mysql_pass" => "pass",
            "mysql_user" => "root",
            "mysql_host" => "1.2.3.4",
            "cpcloud"    => 0
        },
        "profile_deleted" => "test"
    }

=cut

sub remote_mysql_delete_profile {
    my ( $args, $metadata ) = @_;

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';

    my ( $profile_name, $deleted_profile_hr );
    try {
        $profile_name = $args->{'name'} || die Cpanel::Exception::create( 'MissingParameter', 'Missing parameter: [_1]', ['name'] );
        my $profile_manager = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new();

        my $saved_profiles_hr = $profile_manager->read_profiles();
        $deleted_profile_hr = $saved_profiles_hr->{$profile_name} || die Cpanel::Exception::create( 'RecordNotFound', 'No profile named “[_1]” found on the system.', [$profile_name] );
        $profile_manager->delete_profile($profile_name);
        $profile_manager->save_changes_to_disk();
    }
    catch {
        _handle_failure( $metadata, { 'action' => 'delete', 'exception' => $_ } );
    };
    return if !$metadata->{'result'};

    return { 'profile_deleted' => $profile_name, 'profile_details' => $deleted_profile_hr };
}

=item B<remote_mysql_validate_profile>

Validates the specified Remote MySQL profile by attempting to connect/verify the connection details.

B<Input>: Takes two hashrefs:

    * First hashref must contain details about the profile to validate. This hash must contain:

            name - The name of the MySQL profile to validate.

    * Second hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the validation on success.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        "profile_validated" => "test"
    }

=cut

sub remote_mysql_validate_profile {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $profile_name;
    try {
        $profile_name = $args->{'name'} || die Cpanel::Exception::create( 'MissingParameter', 'Missing parameter: [_1]', ['name'] );
        Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new( { 'read_only' => 1 } )->validate_profile($profile_name);
    }
    catch {
        _handle_failure( $metadata, { 'action' => 'validate', 'exception' => $_ } );
    };
    return if !$metadata->{'result'};

    return { 'profile_validated' => $profile_name };
}

=item B<remote_mysql_initiate_profile_activation>

Initiates the activation process for the specified Remote MySQL profile.

B<Input>: Takes two hashrefs:

    * First hashref must contain details about the profile to validate. This hash must contain:

            name - The name of the MySQL profile to validate.

    * Second hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the activation job that was dispatched.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        "activation_job_started" => "pid?"
    }

=cut

sub remote_mysql_initiate_profile_activation {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my ( $profile_name, $activation_id );
    try {
        $profile_name = $args->{'name'} || die Cpanel::Exception::create( 'MissingParameter', 'Missing parameter: [_1]', ['name'] );
        die Cpanel::Exception::create( 'RemoteMySQL::ActivationInProgress', 'The system can only activate one profile at a time.' )
          if Cpanel::MysqlUtils::RemoteMySQL::ActivationJob->get_progress()->{'job_in_progress'};

        $activation_id = Cpanel::ForkAsync::do_in_child(
            sub {
                Cpanel::CloseFDs::redirect_standard_io_dev_null();
                open( STDERR, '>>', '/usr/local/cpanel/logs/error_log' ) || die "Could not redirect STDERR to /usr/local/cpanel/logs/error_log: $!";
                exec( '/usr/local/cpanel/scripts/manage_mysql_profiles', '--activate', $profile_name );
            }
        );
    }
    catch {
        _handle_failure( $metadata, { 'action' => 'activate', 'exception' => $_ } );
    };
    return if !$metadata->{'result'};

    return { 'activation_job_started' => $activation_id };
}

=item B<remote_mysql_monitor_profile_activation>

Monitors and returns informtion about a running activation process.

B<Input>: Takes a hashref:

    * Hashref is a reference to the metadata.

B<Output>: Returns a hashref containing details about the activation job.
Sets the 'result', 'reason' and 'errors' array in the C<$metadata> hashref accordingly on failure.

Example of returned hash:

    {
        'state' => 'in progress',
        'steps done' => [
            { 'title' => 'validated profile' },
            { 'title' => 'updated local root .my.cnf' },
            { 'title' => 'updated apps using mysql' },
            ...
        ],
    }

=cut

sub remote_mysql_monitor_profile_activation {
    my ( $args, $metadata ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my $progress;
    try {
        $progress = Cpanel::MysqlUtils::RemoteMySQL::ActivationJob->get_progress();
    }
    catch {
        _handle_failure( $metadata, { 'action' => 'activate', 'exception' => $_ } );
    };
    return if !$metadata->{'result'};

    return $progress;
}

sub _create_or_update_profile {
    my ( $args, $metadata, $opts ) = @_;

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    my ( $profile_name, $profile_hr );
    try {
        my $profile_manager = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new();
        ( $profile_name, $profile_hr ) = $profile_manager->create_profile( $args, $opts );
        $profile_manager->save_changes_to_disk();
    }
    catch {
        _handle_failure( $metadata, { 'action' => ( $opts ? 'update' : 'create' ), 'exception' => $_ } );
    };
    return if !$metadata->{'result'};

    return { 'profile_saved' => $profile_name, 'profile_details' => $profile_hr };
}

sub _get_remote_mysql_pass_and_port {
    my $ssh_obj = shift;
    my ( $remote_mysql_pass, $remote_mysql_port );
    my ( $cat_ok, $remote_my_cnf ) = $ssh_obj->cat_file('/root/.my.cnf');
    if ( !$cat_ok ) {
        die Cpanel::Exception::create( 'RemoteSSHConnectionFailed', 'Failed to make an [asis,SSH] connection to the remote server because of an error: [_1].', [$remote_my_cnf] );
    }

    foreach my $line ( split( m{\n}, $remote_my_cnf ) ) {
        chomp $line;
        if ( $line =~ /^pass(?:word)?\s*=\s*(.*)/ ) {
            $remote_mysql_pass = $1;
            $remote_mysql_pass =~ s/^\"//g;
            $remote_mysql_pass =~ s/\"$//g;
        }
        elsif ( $line =~ /^port\s*=\s*(\d*)/ ) {
            $remote_mysql_port = $1;
            $remote_mysql_port =~ s/^\"//g;
            $remote_mysql_port =~ s/\"$//g;
        }
    }

    $remote_mysql_pass ||= Cpanel::Rand::Get::getranddata(32);
    $remote_mysql_port ||= 3306;

    return ( $remote_mysql_pass, $remote_mysql_port );
}

sub _generate_remote_script {

    my $remote_mysql_pass = shift;
    my $script_path       = '/root/.mysqlscript';

    my $mainip                 = Cpanel::DIp::MainIP::getmainserverip();
    my $hostname               = Cpanel::Sys::Hostname::gethostname();
    my $safe_remote_mysql_pass = Cpanel::MysqlUtils::Quote::safesqlstring($remote_mysql_pass);

    if ( open( my $script_fh, '>', $script_path ) ) {
        foreach my $template (qw(/usr/local/cpanel/whostmgr/libexec/remote_host_calculation_shell_code.template /usr/local/cpanel/whostmgr/libexec/remote_mysql_setup.template)) {
            if ( open( my $template_script, '<', $template ) ) {
                while ( readline $template_script ) {
                    s/\[\% data.hostname \%\]/$hostname/g;
                    s/\[\% data.mainip \%\]/$mainip/g;
                    s/\[\% data.saferemoterootmysqlpass \%\]/$safe_remote_mysql_pass/g;

                    print {$script_fh} $_;
                }
                close $template_script;
            }
            else {
                die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $template, error => $!, mode => '<' ] );
            }
        }
        close $script_fh;
    }
    else {
        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $script_path, error => $!, mode => '>' ] );
    }
    return $script_path;
}

sub _copy_script_to_remote {
    my ( $ssh_obj, $script_path ) = @_;
    require Whostmgr::Remote;
    if (
        !(
            $ssh_obj->remotescriptcopy(
                "txt"     => "Copying Database Script",
                "srcfile" => $script_path,
            )
        )[$Whostmgr::Remote::STATUS]
    ) {
        return;
    }
    return 1;
}

sub _run_script_on_remote {
    my ( $ssh_obj, $script_path ) = @_;
    require Whostmgr::Remote;
    if (
        !(
            $ssh_obj->remoteexec(
                "txt"          => "Running Database Script",
                "cmd"          => "sh $script_path; rm -f $script_path",
                "returnresult" => 1,
            )
        )[$Whostmgr::Remote::STATUS]
    ) {
        return;
    }
    return 1;
}

sub _handle_failure {
    my ( $metadata, $opts ) = @_;

    _initialize();
    my $action     = $opts->{'action'} || 'update';
    my $exception  = $opts->{'exception'};
    my $exceptions = try { $exception->isa('Cpanel::Exception::Collection') } ? $exception->get('exceptions') : ref $exception eq 'HASH' ? $exception->{'exceptions'} : [$exception];
    $metadata->{'result'}      = 0;
    $metadata->{'reason'}      = $locale->maketext( 'Failed to “[_1]” Remote database profile. [quant,_2,error,errors] occurred.', $action, scalar @{$exceptions} );
    $metadata->{'error_count'} = scalar @{$exceptions};
    _populate_errors( $metadata, $exceptions );
    return 1;
}

sub _populate_errors {
    my ( $metadata, $exceptions_ar ) = @_;

    $metadata->{'errors'} = [];
    foreach my $error ( @{$exceptions_ar} ) {
        push @{ $metadata->{'errors'} }, Cpanel::Exception::get_string( $error, 'no_id' );
    }
    return 1;
}

sub _initialize {
    $locale ||= Cpanel::Locale->get_handle();
    return 1;
}

=back

=cut

1;
