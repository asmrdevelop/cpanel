package Cpanel::MysqlUtils::RemoteMySQL::ProfileManager;

# cpanel - Cpanel/MysqlUtils/RemoteMySQL/ProfileManager.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic (RequireUseWarnings)

use Cpanel::Exception                     ();
use Cpanel::IP::Loopback                  ();
use Cpanel::Validate::IP                  ();
use Cpanel::Validate::Domain::Tiny        ();
use Cpanel::Validate::Username            ();
use Cpanel::MysqlUtils::Version           ();
use Cpanel::Transaction::File::JSON       ();    # PPI USE OK -- used by _initialize
use Cpanel::Transaction::File::JSONReader ();    # PPI USE OK -- used by _initialize
use Cpanel::MariaDB                       ();
use Cpanel::MysqlUtils::MyCnf::Basic      ();
use Cpanel::MysqlUtils::Versions          ();
use Cpanel::LoadModule                    ();

=head1 NAME

Cpanel::MysqlUtils::RemoteMySQL::ProfileManager - Create and manage Remote MySQL profiles.

=head1 SYNOPSIS

    my $profile_manager = Cpanel::MysqlUtils::RemoteMySQL::ProfileManager->new();
    my $profiles_ar = $profile_manager->profiles();
    $profile_manager->create_profile( { 'name' => 'new mysql server', 'mysql_user' => 'user', 'mysql_pass' => 'pass' } );
    $profile_manager->delete_profile( 'new mysql server' );

=cut

# Used for mocking in unit tests
sub _base_dir                  { return "/var/cpanel/mysql/remote_profiles"; }
sub REMOTE_MYSQL_PROFILES_FILE { return _base_dir() . '/profiles.json'; }

=head1 Methods

=over 8

=item B<new>

Constructor.

Takes a hashref that can be used to define how the Transaction object is built:

    'read_only' => 1 or 0.
                   Setting this option to '1', makes the internal transaction object 'read only',
                   and disables the following functions (they will simply return false):

                   create_profile
                   delete_profile
                   save_changes_to_disk
                   mark_profile_as_active
                   generate_active_profile_if_none_set

=cut

sub new {
    my ( $class, $opts ) = @_;
    $opts = {} if !$opts || ref $opts ne 'HASH';

    my $self = bless {}, $class;
    $self->_initialize($opts);

    return $self;
}

=item B<create_profile>

Object method.

B<Input>: Takes two hashrefs as input:

    * First hashref is required, and must be a hashref containing details about the new MySQL profile to save.
    * Second hashref is optional, and allows to specify the 'overwrite' option that will determine whether an existing profile is overwritten or not.

B<Output>: Dies on failure with Cpanel::Exception.
Returns a 1 on success in scalar context.
Returns a list containing the profile name, and a hashref detailing the newly saved profile in non-scalar context.

Does NOT write changes to disk until C<save_changes_to_disk> is called.

=cut

sub create_profile {
    my ( $self, $profile_hr, $opts_hr ) = @_;
    return if $self->{'_read_only'};

    if ( !$profile_hr || 'HASH' ne ref $profile_hr ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a [asis,hashref] containing details for a [asis,MySQL] remote profile.' );
    }
    $opts_hr = {} if !$opts_hr || 'HASH' ne ref $opts_hr;

    my $profile_name = $profile_hr->{'name'} || die Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', ['name'] );

    my $profiles = $self->read_profiles();
    if ( exists $profiles->{$profile_name} ) {
        die Cpanel::Exception::create( 'NameConflict', 'A Remote [asis,MySQL] profile named “[_1]” already exists.', [$profile_name] ) if !$opts_hr->{'overwrite'};
        foreach my $key_name (qw(mysql_host mysql_port mysql_user mysql_pass setup_via active cpcloud)) {
            $profile_hr->{$key_name} //= $profiles->{$profile_name}->{$key_name};
        }
    }

    $profile_hr = _sanitize_profile_hr($profile_hr);
    $profiles->{$profile_name} = $profile_hr;
    $self->{'_transaction_obj'}->set_data($profiles);
    return wantarray ? ( $profile_name, $profile_hr ) : 1;
}

=item B<read_profiles>

Object method.

B<Input>: None.

B<Output>: Dies on failure with Cpanel::Exception. Returns a hashref containing the profiles currently stored in the C<REMOTE_MYSQL_PROFILES_FILE> file.

=cut

sub read_profiles {
    my $self = shift;
    my $data = $self->{'_transaction_obj'}->get_data();

    my $profiles = ( ref $data eq 'SCALAR' ? ${$data} : $data ) || {};
    return $profiles;
}

=item B<delete_profile>

Object method.

B<Input>: String containing the name of the profile to delete.

B<Output>: Dies on failure with Cpanel::Exception. Returns a 1 indicating success.

Does NOT write changes to disk until C<save_changes_to_disk> is called.

=cut

sub delete_profile {
    my ( $self, $profile_to_delete ) = @_;
    return if $self->{'_read_only'};

    my $profiles = $self->read_profiles();
    die Cpanel::Exception::create( 'InvalidParameter', 'You cannot delete the active [asis,MySQL] profile: [_1]', [$profile_to_delete] )
      if ( $profiles->{$profile_to_delete} && $profiles->{$profile_to_delete}->{'active'} );
    delete $profiles->{$profile_to_delete};

    $self->{'_transaction_obj'}->set_data($profiles);
    return 1;
}

=item B<save_changes_to_disk>

Object method.

B<Input>: None.
B<Output>: Dies on failure with Cpanel::Exception. Writes the changes out to the C<REMOTE_MYSQL_PROFILES_FILE> file.

=cut

sub save_changes_to_disk {
    my $self = shift;
    return if $self->{'_read_only'};
    my $ret = $self->{'_transaction_obj'}->save_or_die();

    _update_caches();
    return $ret;
}

=item B<validate_profile>

Object method. Attempts to vaidate the profile by doing the following:

    * Connects to the MySQL server with the credentials in the specified profile.
    * Checks the privileges of the connected user, and checks to ensure that it has
      ALL privileges on all tables ('*.*'), and has the GRANT option.

B<Input>: String containing the name of the profile to validate.

B<Output>: Dies on failure with Cpanel::Exception. Returns a 1 indicating success.

=cut

sub validate_profile {
    my ( $self, $profile_name ) = @_;
    my $profile_hr = $self->read_profiles()->{$profile_name}
      || die Cpanel::Exception::create( 'RecordNotFound', 'No profile named “[_1]” found on the system.', [$profile_name] );

    my $dbh = _generate_dbi_handle_for_profile($profile_hr)
      || die Cpanel::Exception::create( 'ConnectionFailed', 'Unable to connect to the [asis,MySQL] host “[_1]”. Connection failed with error: [_2]', [ $profile_hr->{'mysql_host'}, $DBI::errstr ] );

    my $nice_version = Cpanel::MysqlUtils::Version::mysql_version_id_to_version( $dbh->{'mysql_serverversion'}, 2 );
    my $is_mariadb   = Cpanel::MariaDB::dbh_is_mariadb($dbh);
    my $nice_name    = $is_mariadb ? 'MariaDB' : 'MySQL';

    my @supported_mariadb = Cpanel::MysqlUtils::Versions::get_supported_mariadb_versions();
    my @supported_mysql   = Cpanel::MysqlUtils::Versions::get_supported_mysql_versions();

    my @supported = $is_mariadb ? @supported_mariadb : @supported_mysql;

    my @is_supported = grep { $nice_version eq $_ } @supported;

    if ( !@is_supported ) {

        die Cpanel::Exception::create(
            'Unsupported',
            'The system does not support [_1] [_2] running on the remote server.',
            [ $nice_name, $nice_version ]
        );

    }

    _check_user_privileges($dbh);

    return _check_default_auth_plugin($dbh);
}

=item B<mark_profile_as_active>

Object method. Marks the specified profile as active.

B<Input>: String containing the name of the profile to mark as active.

B<Output>: Dies on failure with Cpanel::Exception. Returns a 1 indicating success.

Does NOT write changes to disk until C<save_changes_to_disk> is called.

=cut

sub mark_profile_as_active {
    my ( $self, $profile_name ) = @_;
    return if $self->{'_read_only'};

    my $profiles   = $self->read_profiles();
    my $profile_hr = $profiles->{$profile_name}
      || die Cpanel::Exception::create( 'RecordNotFound', 'No profile named “[_1]” found on the system.', [$profile_name] );

    foreach my $current_active_profile ( grep { $profiles->{$_}->{'active'} } ( keys %{$profiles} ) ) {
        $profiles->{$current_active_profile}->{'active'} = 0;
    }
    $profile_hr->{'active'} = 1;

    $profiles->{$profile_name} = $profile_hr;
    $self->{'_transaction_obj'}->set_data($profiles);
    return 1;
}

=item B<get_active_profile>

Object method. Returns the name of the active profile.

B<Input>: An optional Boolean value can be passed to indicate whether the 'exception' should be suppressed or not.
If a 'true' value is passed, then the exception is suppressed when no active profile is found.
If no value, or a false value is passed, then an exception is raised when no active profile is found.

B<Output>: Dies on failure with Cpanel::Exception. Returns a string containing the name of the active profile on success.

=cut

sub get_active_profile {
    my $self     = shift;
    my $dont_die = shift || 0;

    my $current_profiles = $self->read_profiles();
    my ($active_profile) = grep { $current_profiles->{$_}->{'active'} } ( keys %{$current_profiles} );
    die Cpanel::Exception::create( 'RecordNotFound', 'No active profile found on the system.' )
      if !$active_profile && !$dont_die;

    return $active_profile;
}

=item B<generate_active_profile_if_none_set>

Object method. Generates a MySQL profile from the current MySQL settings if no profile is marked active.

This method is used in the 'Install::ConfigureRemoteMysqlProfile' post install/upgrade task.

B<Input>: None.

B<Output>: Dies on failure with Cpanel::Exception. Returns a 1 indicating success.

=cut

sub generate_active_profile_if_none_set {
    my ( $self, $force ) = @_;
    return if $self->{'_read_only'};

    my $active_profile = $self->get_active_profile('dont_die');
    if ( !$active_profile || $force ) {
        $active_profile = {
            'mysql_user' => Cpanel::MysqlUtils::MyCnf::Basic::getmydbuser('root') || 'root',
            'mysql_pass' => Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass('root'),
            'mysql_host' => Cpanel::MysqlUtils::MyCnf::Basic::getmydbhost('root') || 'localhost',
            'mysql_port' => Cpanel::MysqlUtils::MyCnf::Basic::getmydbport('root') || 3306,
            'setup_via'  => 'Auto-Migrated active profile',
            'cpcloud'    => 0,
        };
        if ( Cpanel::MysqlUtils::MyCnf::Basic::is_local_mysql( $active_profile->{'mysql_host'} ) ) {
            $active_profile->{'name'} = 'localhost';
        }
        else {
            # profile names are currently limited to a length of 32 chars.
            $active_profile->{'name'} = substr( 'remote_host_' . $active_profile->{'mysql_host'}, 0, 32 );
            $active_profile->{'name'} =~ s/[^\w\s\-]/_/g;
        }

        # If no profile is set to active, then forcibly create a new profile for the 'active' mysql configuration.
        if ( $self->create_profile( $active_profile, { 'overwrite' => 1 } ) ) {
            $self->mark_profile_as_active( $active_profile->{'name'} );
            $self->save_changes_to_disk();
        }
    }
    return 1;
}

=item B<is_active_profile_cpcloud>

Object method. Checks if the current active profile is a cPanel Cloud deployment.

B<Input>: None.

B<Output>: Returns a 1 indicating that this is an active cPanel Cloud deployment.
Returns 0 if there is no existing active profile or the current active profile is not cpcloud.

=cut

sub is_active_profile_cpcloud {
    my ($self) = @_;

    my $active_profile_name = $self->get_active_profile('dontdie');
    return 0 if !$active_profile_name;

    my $all_profiles   = $self->read_profiles();
    my $active_profile = $all_profiles->{$active_profile_name};

    return $active_profile && $active_profile->{'cpcloud'} ? 1 : 0;
}

sub _generate_dbi_handle_for_profile {
    my $profile_hr = shift;
    my $host       = $profile_hr->{'mysql_host'};
    $host = "[$host]" if Cpanel::Validate::IP::is_valid_ipv6($host);

    Cpanel::LoadModule::load_perl_module('DBI');

    return DBI->connect(
        "DBI:mysql:host=$host;port=$profile_hr->{'mysql_port'};mysql_connect_timeout=5",
        $profile_hr->{'mysql_user'},
        $profile_hr->{'mysql_pass'},
        {
            'PrintError' => 0,
            'RaiseError' => 0,
        }
    );
}

# CPANEL-32591: phpMyAdmin does not support caching_sha2_password
sub _check_default_auth_plugin {
    my $dbh                 = shift;
    my $default_auth_plugin = _fetch_default_auth_plugin($dbh);

    if ( $default_auth_plugin eq 'caching_sha2_password' ) {
        die Cpanel::Exception::create(
            'RemoteMySQL::UnsupportedAuthPlugin',
            'The [asis,MySQL] server uses the “[_1]” authentication plugin, which is not currently supported.',
            ['caching_sha2_password']
        );
    }

    return 1;
}

sub _fetch_default_auth_plugin {
    my $dbh   = shift;
    my $query = 'SHOW VARIABLES WHERE VARIABLE_NAME = "default_authentication_plugin"';

    local $dbh->{FetchHashKeyName} = 'NAME_lc';
    my $sth = $dbh->prepare($query);
    $sth->execute();

    my $auth_plugin_hr = $sth->fetchrow_hashref();
    return $auth_plugin_hr && $auth_plugin_hr->{'value'} || '';
}

sub _check_user_privileges {
    my $dbh           = shift;
    my $privileges_ar = _fetch_user_privileges($dbh);

    my @required_privs = (
        'SELECT',         'ALTER', 'ALTER ROUTINE', 'CREATE',
        'CREATE ROUTINE', 'CREATE TEMPORARY TABLES',
        'CREATE USER',    'CREATE VIEW', 'DELETE',
        'DROP',           'EXECUTE',     'EVENT',       'INDEX', 'INSERT',
        'REFERENCES',     'RELOAD',      'UPDATE',      'SHOW DATABASES',
        'SHOW VIEW',      'TRIGGER',     'LOCK TABLES', 'PROCESS'
    );

    Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Grants');
    foreach my $priv_statement ( @{$privileges_ar} ) {
        return 1 if $priv_statement =~ m/^GRANT ALL PRIVILEGES ON \*\.\* .* WITH GRANT OPTION/;
        next     if $priv_statement !~ /WITH GRANT OPTION/;

        my $grant = eval { Cpanel::MysqlUtils::Grants->new($priv_statement); } or next;
        my %privs = map { $_ => 1 } split( /, /, $grant->db_privs() );
        next if grep { !exists $privs{$_} } @required_privs;

        return 1;
    }
    die Cpanel::Exception::create( 'RemoteMySQL::InsufficientPrivileges', 'The [asis,MySQL] user “[_1]” does not have the proper [asis,PRIVILEGES] to act as a [asis,MySQL superuser].', [ $dbh->{'Username'} ] );
}

sub _fetch_user_privileges {
    my $dbh   = shift;
    my $query = 'SHOW GRANTS FOR CURRENT_USER();';
    my $sth   = $dbh->prepare($query);
    $sth->execute();

    my @grants;
    while ( my $data = $sth->fetchrow_arrayref() ) {
        push @grants, $data->[0];
    }
    return \@grants;
}

sub _sanitize_profile_hr {
    my $profile_hr = shift;

    my ( @err_collection, $sanitized_profile_hr );
    my %required_keys = map { $_ => 1 } (qw(mysql_host mysql_port mysql_user mysql_pass));
    my @optional_keys = qw( setup_via active cpcloud  );

    foreach my $required_key ( keys %required_keys ) {
        push @err_collection, Cpanel::Exception::create( 'MissingParameter', 'The parameter “[_1]” is required.', [$required_key] ) if not exists $profile_hr->{$required_key};
    }
    die Cpanel::Exception::create( 'Collection', [ exceptions => \@err_collection ] ) if scalar @err_collection;

    my $validation_tests = {
        'name'       => sub { return $_[0] =~ m/^[a-zA-Z][\w\s\-]{1,31}$/ },
        'mysql_host' => sub { return ( Cpanel::IP::Loopback::is_loopback( $_[0] ) || Cpanel::Validate::IP::is_valid_ip( $_[0] ) || Cpanel::Validate::Domain::Tiny::validdomainname( $_[0], 1 ) ); },
        'mysql_user' => sub { return Cpanel::Validate::Username::is_valid( $_[0] ); },
        'mysql_pass' => sub { return length $_[0] ? 1 : 0; },
        'mysql_port' => sub { return $_[0] =~ m/^\d+$/ && 1 <= $_[0] && $_[0] <= 65535; },
        'active'     => sub { return $_[0] =~ m/^[01]$/; },
        'cpcloud'    => sub { return $_[0] =~ m/^[01]$/; },
    };

    # cpcloud should default to 0 unless passed in.
    $profile_hr->{'cpcloud'} //= 0;

    foreach my $key ( sort keys %{$profile_hr} ) {
        if ( exists $validation_tests->{$key} && !$validation_tests->{$key}->( $profile_hr->{$key} ) ) {
            push @err_collection, Cpanel::Exception::create( 'InvalidParameter', 'The [asis,MySQL] parameter “[_1]” specified is not valid: [_2]', [ $key, $profile_hr->{$key} ] );
        }
        elsif ( exists $required_keys{$key} || grep { $key eq $_ } @optional_keys ) {
            $sanitized_profile_hr->{$key} = $profile_hr->{$key};
        }
    }
    die Cpanel::Exception::create( 'Collection', [ exceptions => \@err_collection ] ) if scalar @err_collection;
    $sanitized_profile_hr->{'setup_via'} //= 'Unspecified';

    # make a profile non-active by default, unless the option is passed in.
    $sanitized_profile_hr->{'active'} //= 0;

    return $sanitized_profile_hr;
}

=item B<update_local_profiles_if_needed>

Object method. Updates the password on localhost profiles for the root user, if the password has changed.

B<Input>: String representing the new password to set on the localhost profile.

B<Output>: Dies on failure with Cpanel::Exception. Returns a 1 indicating success.

=cut

sub update_local_profiles_if_needed {
    my ( $self, $password ) = @_;
    return if $self->{'_read_only'};

    my $updated = 0;

    my $current_profiles    = $self->read_profiles();
    my @local_profile_names = grep { Cpanel::MysqlUtils::MyCnf::Basic::is_local_mysql( $current_profiles->{$_}->{'mysql_host'} ) && $current_profiles->{$_}->{'mysql_user'} eq 'root' } ( keys %{$current_profiles} );

    foreach my $profile (@local_profile_names) {
        next if ( $current_profiles->{$profile}->{'mysql_pass'} eq $password );
        $current_profiles->{$profile}->{'mysql_pass'} = $password;
        $updated = 1;
    }

    if ($updated) {
        $self->{'_transaction_obj'}->set_data($current_profiles);
        $self->save_changes_to_disk();
    }

    return 1;
}

=item B<update_password_for_active_profile_host>

Object method. Updates the password for all profiles matching the active profile's host and user.

B<Input>: String representing the new password to set.

B<Output>: Dies on failure with Cpanel::Exception. Returns a 1 indicating success.

=cut

sub update_password_for_active_profile_host {
    my ( $self, $new_password ) = @_;

    return if $self->{'_read_only'};

    my $profile_data_for = $self->read_profiles();
    my $active_profile   = $profile_data_for->{ $self->get_active_profile('dontdie') };

    return if !$active_profile;

    my $active_profile_host = $active_profile->{'mysql_host'} || '';

    my $changes_made = 0;

    # Apply password change to all profiles with the same host and username.
    foreach my $profile ( values %{$profile_data_for} ) {
        if (   $profile->{'mysql_host'} ne $active_profile->{'mysql_host'}
            || $profile->{'mysql_user'} ne $active_profile->{'mysql_user'} ) {
            next;
        }
        if ( $profile->{'mysql_pass'} ne $new_password ) {
            $profile->{'mysql_pass'} = $new_password;
            $changes_made = 1;
        }
    }

    if ($changes_made) {
        $self->{'_transaction_obj'}->set_data($profile_data_for);
        $self->save_changes_to_disk();
    }

    return 1;
}

sub _initialize {
    my ( $self, $opts ) = @_;

    if ( !-d _base_dir() ) {
        require File::Path;
        File::Path::make_path( _base_dir(), { 'mode' => 0600 } );
    }
    elsif ( !( ( stat _base_dir() )[2] & 044 ) ) {
        chmod 0600, _base_dir();
    }

    my $module = 'Cpanel::Transaction::File::JSON';
    if ( $opts && $opts->{'read_only'} ) {
        $module = 'Cpanel::Transaction::File::JSONReader';
        $self->{'_read_only'} = 1;
    }

    $self->{'_transaction_obj'} = $module->new(
        path        => REMOTE_MYSQL_PROFILES_FILE(),
        permissions => 0600,
        ownership   => ['root'],
    );

    return 1;
}

=back

=cut

sub _update_caches {
    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 5, 'build_global_cache' );
    require Whostmgr::Templates::Command::Directory;
    Whostmgr::Templates::Command::Directory::clear_cache_dir();
    return;
}

1;
