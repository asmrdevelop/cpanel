package Cpanel::Server::FPM::Manager;

# cpanel - Cpanel/Server/FPM/Manager.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

=encoding UTF-8

Cpanel::Server::FPM::Manager

=head1 DESCRIPTION

  Manage the FPM Server for cpsrvd / cpdavd( cpdavd not implemented )

=head1 SYNOPSIS

  use Cpanel::Server::FPM::Manager;

  Cpanel::Server::FPM::Manager::add_user($user);
  Cpanel::Server::FPM::Manager::regenerate_user($user);
  Cpanel::Server::FPM::Manager::remove_user($user);
  Cpanel::Server::FPM::Manager::sync_config_files();
  Cpanel::Server::FPM::Manager::reload();

=cut

=head1 DESCRIPTION

=cut

use strict;

use Errno                  ();
use Cpanel::LoadModule     ();
use Cpanel::PwCache::Build ();
use Cpanel::PwCache        ();
use Cpanel::Exception      ();

use Cpanel::Autodie                      ();
use Cpanel::AdvConfig                    ();
use Cpanel::Mkdir                        ();
use Cpanel::PwCache                      ();
use Cpanel::ConfigFiles                  ();
use Cpanel::Config::Users                ();
use Cpanel::OrDie                        ();
use Cpanel::PsParser                     ();
use Cpanel::LoadModule                   ();
use Cpanel::Exception                    ();
use Cpanel::ProcessInfo                  ();
use Cpanel::Services                     ();
use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::Logd::Dynamic                ();

our $SERVICE              = 'cpanel_php_fpm';
our $SERVICE_PROCESS_NAME = 'php-fpm';
our $LOG_DIR              = "/usr/local/cpanel/logs/php-fpm";
our $CONFIG_FILE          = '/usr/local/cpanel/etc/php-fpm.conf';
our $PID_FILE             = '/var/run/cpanel_php_fpm.pid';
our $ERROR_LOG            = "$LOG_DIR/error.log";

our @LOG_TYPES = (qw(error slow));

our %cpanel_php_fpm_users = (
    cpanelroundcube  => 1,
    cpanelphpmyadmin => 1,
);

=head2 add_user( USER )

=head3 Purpose

Adds a user from the FPM configuration

=head3 Arguments

=over

=item * USER: string (required) - The name of the cPanel user account.

=back

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception.

=cut

sub add_user {
    my ($user) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);
    my ( $gid, $homedir ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 3, 7 ];

    _ensure_log_dir_for_user( $user, $gid );

    regenerate_user($user);

    foreach my $type (@LOG_TYPES) {
        Cpanel::Logd::Dynamic::create_logd_link_entry( _log_name_for_user_type( $user, $type ), "$Cpanel::ConfigFiles::FPM_ROOT/$user/logs/$type.log" );
    }

    return 1;
}

=head2 regenerate_user( USER )

=head3 Purpose

Regenerate the configuration for a user from the FPM configuration
when their account has been modified

=head3 Arguments

=over

=item * USER: string (required) - The name of the cPanel user account.

=back

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

sub regenerate_user {
    my ($user) = @_;

    my ( $gid, $homedir ) = ( Cpanel::PwCache::getpwnam_noshadow($user) )[ 3, 7 ];
    Cpanel::OrDie::multi_return(
        sub {
            Cpanel::AdvConfig::generate_config_file(
                {    #
                    'service' => $SERVICE,                                           #
                    'force'   => 0,                                                  #
                    'user'    => $user,
                    'homedir' => $homedir,
                    'type'    => $cpanel_php_fpm_users{$user} ? 'cpanel' : 'user'    #
                }    #
            );
        },
    );

    return 1;
}

=head2 remove_user( USER )

=head3 Purpose

Remove a user from the FPM configuration

=head3 Arguments

=over

=item * USER: string (required) - The name of the cPanel user account.

=back

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

sub remove_user {
    my ($user) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($user);

    Cpanel::Autodie::unlink_if_exists("$Cpanel::ConfigFiles::FPM_CONFIG_ROOT/$user.conf");

    foreach my $type (@LOG_TYPES) {
        Cpanel::Logd::Dynamic::delete_logd_link_entry( _log_name_for_user_type( $user, $type ) );
    }

    my $err;
    Cpanel::LoadModule::load_perl_module('File::Path');
    'File::Path'->can('remove_tree')->( "$Cpanel::ConfigFiles::FPM_ROOT/$user", { error => \$err } );
    if (@$err) {
        my ( $file, $message ) = %{ $err->[0] };
        die Cpanel::Exception->create_raw("$file: $message");
    }

    return 1;
}

=head2 sync_config_files()

=head3 Purpose

Enumerate all the users on the system and add missing config files as well as
remove config files that are present for non-existant users.

=head3 Arguments

None

=head3 Returns

=over

=item 1 on success

=back

If an error occurred the function will generate an exception

=cut

sub sync_config_files {
    _ensure_fpm_root();

    Cpanel::Mkdir::ensure_directory_existence_and_mode( $LOG_DIR, 0700 );
    Cpanel::Autodie::chown( 0, 0, $LOG_DIR );

    my %CPUSERS = map { $_ => 1 } ( Cpanel::Config::Users::getcpusers(), keys %cpanel_php_fpm_users );

    my @users_with_fpm = get_users_with_fpm_configured();
    my ( @unlink, @rmtree );
    foreach my $user (@users_with_fpm) {
        if ( !$CPUSERS{$user} && $user !~ /^_/ ) {
            push @rmtree, "$Cpanel::ConfigFiles::FPM_ROOT/$user";
            push @unlink, "$Cpanel::ConfigFiles::FPM_CONFIG_ROOT/$user.conf";
        }
    }
    {
        local $!;
        foreach my $file (@unlink) {
            unlink($file)
              or _logger()->warn("The system failed to unlink the file “$file” because of an error: $!");
        }
    }
    my $err;
    Cpanel::LoadModule::load_perl_module('File::Path');
    'File::Path'->can('remove_tree')->( @rmtree, { error => \$err } );
    if (@$err) {
        my ( $file, $message ) = %{ $err->[0] };
        _logger()->warn("The system failed to remove the directory tree “$file” because of an error: $message");
    }

    Cpanel::PwCache::Build::init_passwdless_pwcache();
    my $pwcache_ref = Cpanel::PwCache::Build::fetch_pwcache();

    # Don't make config for cpanelroundcube if we're on sqlite, as it uses the user's pool in that case
    require Cpanel::Config::LoadCpConf;
    my $conf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    delete $CPUSERS{'cpanelroundcube'} if ( $conf_ref->{'roundcube_db'} && $conf_ref->{'roundcube_db'} eq 'sqlite' );

    foreach my $pw ( grep { $CPUSERS{ $_->[0] } } @$pwcache_ref ) {
        local $@;
        eval { add_user( $pw->[0] ); };
        _logger()->warn("Failed to generate “$SERVICE” configuration file for “$pw->[0]”: $@") if $@;
    }

    return 1;
}

=head2 get_users_with_fpm_configured()

=head3 Purpose

Obtain a list of users that have FPM configured

=head3 Arguments

None

=head3 Returns

=over

=item An array of users that have fpm configured

=back

If an error occurred the function will generate an exception

=cut

sub get_users_with_fpm_configured {
    Cpanel::Autodie::opendir( my $fpm_dh, $Cpanel::ConfigFiles::FPM_CONFIG_ROOT );
    my @users;
    local $!;
    my @confs = grep( m{\.conf$}, readdir($fpm_dh) );
    if ( $! && !( $! == Errno::EBADF() && $^V lt v5.20 ) ) {
        die Cpanel::Exception::create( 'IO::DirectoryReadError', [ path => $Cpanel::ConfigFiles::FPM_CONFIG_ROOT, error => $! ] );
    }
    @users = sort map { s{\.conf$}{}r } @confs;
    return @users;
}

=head2 reload()

=head3 Purpose

Do a graceful reload of the FPM service

=head3 Arguments

None

=head3 Returns

=over

=item 1 on success

=item 0 is returned the process could not be reloaded

=back

If an error occurred the function will generate an exception

=cut

sub reload {
    my @pids = get_master_process_pids();
    return 0 if !@pids;
    return kill( 'USR2', @pids );
}

sub checked_reload {
    local $@;

    require Cpanel::Server::FPM::Manager::Check;

    if ( reload() && eval { Cpanel::Server::FPM::Manager::Check->new()->check() } ) {
        return 1;
    }

    return 0;

}

#perl -MCpanel::Server::FPM::Manager -e 'print Cpanel::Server::FPM::Manager::get_master_process_pids();'

sub get_master_process_pids {

    my %apps = Cpanel::Services::get_running_process_info(
        'pidfile' => $PID_FILE,
        'user'    => 'root',
        'service' => $SERVICE,
        'regex'   => _master_process_regex(),
    );
    my @pids = ( map { $_->{'pid'} } values %apps );
    return @pids;
}

sub _master_process_regex {
    #
    # There is a race condition with process name!
    #
    # On startup the process looks like this:
    # /usr/local/cpanel/3rdparty/sbin/cpanel_php_fpm -y /usr/local/cpanel/etc/php-fpm.conf
    # Once it sets $0 it looks like this:
    # php-fpm: master process (/usr/local/cpanel/etc/php-fpm.conf)
    return qr{(?:/\Q$SERVICE\E|\Q$SERVICE_PROCESS_NAME\E.*\Q$CONFIG_FILE\E)};
}

sub _all_process_regex {
    #
    # There is a race condition with process name!
    #
    # On startup the process looks like this:
    # /usr/local/cpanel/3rdparty/sbin/cpanel_php_fpm -y /usr/local/cpanel/etc/php-fpm.conf
    # Once it sets $0 it looks like this:
    # php-fpm: .....
    return qr{(?:/\Q$SERVICE\E|\Q$SERVICE_PROCESS_NAME\E:)};
}

#perl -MCpanel::Server::FPM::Manager -e 'print Cpanel::Server::FPM::Manager::get_all_pids();'

sub _get_all_pids {
    my @pids_matching_exe;

    my $regex         = _all_process_regex();
    my $mypid         = $$;
    my $parentpid     = getppid();
    my $processes_arr = Cpanel::PsParser::fast_parse_ps( 'resolve_uids' => 0, 'exclude_self' => 1, 'exclude_kernel' => 1 );
    foreach my $process ( @{$processes_arr} ) {
        next if ( $process->{'command'} !~ $regex );
        next if $process->{'pid'} == $mypid || $process->{'pid'} == $parentpid;

        my $exe;
        local $@;
        warn if !eval { $exe = Cpanel::ProcessInfo::get_pid_exe( $process->{'pid'} ); 1 };

        next if !$exe;
        next if $exe !~ m<cpanel/3rdparty>;    # do not kill system php-fpm
        push @pids_matching_exe, $process;
    }
    return @pids_matching_exe;
}

sub get_all_pids {
    return map { $_->{'pid'} } _get_all_pids();
}

# Returns a list of users that have active php-fpm proceses
sub get_all_active_users {

    # php-fpm: pool cpanelphpmyadmin
    my %active_users = map { ( ( $_->{'command'} =~ m{pool\s+(\S+)} )[0] || '' ) => 1 } _get_all_pids();
    delete $active_users{''};
    return \%active_users;
}

sub _ensure_log_dir_for_user {
    my ( $user, $gid ) = @_;

    _ensure_fpm_root();

    my $user_dir = "$Cpanel::ConfigFiles::FPM_ROOT/$user";
    my $log_dir  = "$user_dir/logs";

    #SECURITY: Because the log processor reads from the log directory
    #as root, it is imperative that the user NOT have write permissions
    #to that directory.

    for my $dir ( $user_dir, $log_dir ) {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $dir, 0750 );
        Cpanel::Autodie::chown( 0, $gid, $dir );
    }

    #Because the user doesn’t have write access to the directory,
    #we need to ensure that these log files are readable by the user.
    #NB: Should there ever be more that the user needs to write to,
    #we’ll need to update this section.

    for my $type (@LOG_TYPES) {
        Cpanel::Autodie::open( my $err_fh, '>>', "$log_dir/$type.log" );
        Cpanel::Autodie::chmod( 0660, $err_fh );
        Cpanel::Autodie::chown( -1, $gid, $err_fh );
    }

    return 1;
}

sub _ensure_fpm_root {
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $Cpanel::ConfigFiles::FPM_ROOT, 0751 );
    Cpanel::Autodie::chown( 0, 0, $Cpanel::ConfigFiles::FPM_ROOT );

    Cpanel::Mkdir::ensure_directory_existence_and_mode( $Cpanel::ConfigFiles::FPM_CONFIG_ROOT, 0751 );
    Cpanel::Autodie::chown( 0, 0, $Cpanel::ConfigFiles::FPM_CONFIG_ROOT );

    return 1;
}

my $logger;

sub _logger {
    Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
    return ( $logger ||= Cpanel::Logger->new() );
}

sub _log_name_for_user_type {
    my ( $user, $type ) = @_;
    return "$SERVICE-$user-$type";
}

1;
