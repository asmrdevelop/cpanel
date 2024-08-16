package Whostmgr::Mysql::Upgrade;

# cpanel - Whostmgr/Mysql/Upgrade.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::CloseFDs();
use Cpanel::ForkSync                    ();
use Cpanel::SafeDir::MK                 ();
use Cpanel::FileUtils::Write            ();
use Cpanel::FileUtils::Open             ();
use Cpanel::ConfigFiles                 ();
use Cpanel::MariaDB                     ();
use Cpanel::Chkservd::Tiny              ();
use Cpanel::Config::LoadCpConf          ();
use Cpanel::Config::CpConfGuard         ();
use Cpanel::DataStore                   ();
use Cpanel::Exception                   ();
use Cpanel::Env                         ();
use Cpanel::Kill::Single                ();
use Cpanel::LoadModule                  ();
use Cpanel::FileUtils::TouchFile        ();
use Cpanel::Mysql::Error                ();
use Cpanel::ForkAsync                   ();
use Cpanel::MysqlUtils::Service         ();
use Cpanel::MysqlUtils::Running         ();
use Cpanel::MysqlUtils::MyCnf::Migrate  ();
use Cpanel::MysqlUtils::Version         ();
use Cpanel::MysqlUtils::Versions        ();
use Cpanel::MysqlUtils::Reset           ();
use Cpanel::OS                          ();
use Cpanel::Rlimit                      ();
use Cpanel::SafeRun::Errors             ();
use Cpanel::Services::Restart           ();
use Cpanel::Services::Log::Display      ();
use Cpanel::Output::Formatted::HTML     ();
use Cpanel::Output::Formatted::Terminal ();
use Cpanel::Output::Multi               ();
use Cpanel::Output                      ();
use Cpanel::CPAN::IO::Callback::Write   ();
use Cpanel::Parser::Callback            ();
use Cpanel::SafeRun::Object             ();
use Cpanel::Sys::Setsid::Fast           ();
use Whostmgr::Mysql::Workarounds        ();
use Whostmgr::HTMLInterface::Output     ();
use Cpanel::Pkgr                        ();
use Cpanel::Finally                     ();

use Try::Tiny;

our $SUCCESS_ERROR_CODE              = 0;
our $FAILURE_ERROR_CODE              = 1;
our $MYSQL_UPGRADE_FAILED_ERROR_CODE = 4;

# to prevent them from being reinstalled and failing.
our $LOG_BASE_DIR      = '/var/cpanel/logs';
our $step_counter_file = '/var/cpanel/mysql_upgrade_in_progress';

our $STEP_VERSION_SELECT         = 1;
our $STEP_VERSION_WARNINGS       = 2;
our $STEP_UPGRADE_TYPE_SELECTION = 3;
our $STEP_MYSQL_UPGRADE          = 4;
our $STEP_FINISHED               = 5;

#This is exposed for mocking purposes.
our $FORKSYNC_OBJECT_CLASS = 'Cpanel::ForkSync';

our $current_log;
our $time_id;
my %output_objs;

use constant CHKSRVD_SUSPEND_TIMEOUT         => 120;    # time in sec we ask chksrvd to stop monitoring the service
use constant REFRESH_CHKSRVD_SUSPEND_TIMEOUT => 30;     # extend the chksrvd suspend timeout every X sec.

###########################################################################
#
# Method:
#   upgrade_mysql
#
# Description:
#   Perform a mysql upgrade and returns the status code
#
# Parameters:
#   See upgrade_mysql_with_status
#
# Returns:
#   0 if the upgrade failed
#   1 if the upgrade succeeded
#

sub upgrade_mysql {
    my ($conf) = @_;

    return upgrade_mysql_with_status($conf)->{'status'};
}

# Step 4 - Iterative upgrade of mysql
###########################################################################
#
# Method:
#   upgrade_mysql_with_status
#
# Description:
#   Perform a mysql upgrade and returns the status
#
# Parameters:
#   $conf                  - A hashref of a mysql_upgrade_in_progress file
#
#   Example $conf hashref:
#      {
#        'selected_version' => - The version to upgrade to
#        'upgrade_type'     => - The type of upgrade (interactive|unattended_manual|unattended_automatic)
#        ...
#      }
#
# Returns a hashref of the upgrade status:
# (except sometimes when it dies -- TODO)
#    Example return:
#      {
#          'error_code'    => $MYSQL_UPGRADE_FAILED_ERROR_CODE,
#          'status'        => 0,
#          'error_message' => "The current version of MySQL could not be determined...aborting!",
#      };
sub upgrade_mysql_with_status {
    my ($conf) = @_;

    require Cpanel::Version::Compare;

    $current_log ||= 'upgrade_mysql_with_status';
    start_step( $STEP_MYSQL_UPGRADE, $conf );

    my $selected_version = $conf->{'selected_version'};

    #We add “current_version” in
    #_update_conf_with_current_version_and_check_for_blockers().
    #That function should have been called by now.
    my $current_version = $conf->{'current_version'} = get_current_version( get_output_obj() );

    if ( !$current_version ) {
        return _mysql_upgrade_error( "The system could not determine the currently installed version.", $conf );
    }
    elsif ( !$selected_version ) {
        return _mysql_upgrade_error( "No version to upgrade to was provided.", $conf );
    }
    elsif ( Cpanel::Version::Compare::compare( $selected_version, '<', $current_version ) ) {
        return _mysql_upgrade_error( "The system cannot downgrade, and the selected version, “$selected_version” is lower than the current version, “$current_version”.", $conf );
    }
    elsif ( !grep { $selected_version eq $_ } Cpanel::MysqlUtils::Versions::get_upgrade_path_for_version( $current_version, $selected_version ) ) {
        return _mysql_upgrade_error( "The selected version, “$selected_version” is not available when “$current_version” is installed.", $conf );
    }
    my $reinstall_current_version = $selected_version == $current_version ? 1 : 0;

    my $err;
    try {
        Cpanel::MysqlUtils::Reset::set_root_maximums_to_sane_values();
    }
    catch {
        $err = $_;
    };

    if ($err) {

        # If MySQL is broken we need to be able to reinstall it
        if (
            try {
                $err->isa('Cpanel::Exception::Database::Error')
                  && ( $err->get('error_code') == Cpanel::Mysql::Error::CR_CONNECTION_ERROR() || $err->get('error_code') == Cpanel::Mysql::Error::ER_ACCESS_DENIED_ERROR )
            }
        ) {
            get_output_obj()->warn( Cpanel::Exception::get_string($err) );
        }
        else {
            return _mysql_upgrade_error( Cpanel::Exception::get_string($err), $conf );
        }
    }

    my $run = $FORKSYNC_OBJECT_CLASS->new(
        sub {
            _setup_install_env();

            #clean up any unused mysql pid files found in the datadir
            Cpanel::MysqlUtils::Service::remove_all_dead_pid_files_in_datadir();

            # Remove bench when moving between versions of MySQL. The subsequent install of
            # the next version would assure a re-install of bench if needed (case 38666).
            _remove_install_mysql_bench_packages() if !$reinstall_current_version;

            foreach my $version_to_install ( Cpanel::MysqlUtils::Versions::get_upgrade_path_for_version( $current_version, $selected_version ) ) {

                _save_mysql_state_before_upgrade( 'new_version' => $version_to_install, 'current_version' => $current_version ) || return _mysql_upgrade_error( "Failed to save the server state before upgrade.", $conf );

                my $err;
                try { _install_mysql_version( $version_to_install, $reinstall_current_version ) } catch { $err = $_ };

                if ($err) {

                    # We restore the original $Cpanel::ConfigFiles::MYSQL_CNF if the upgrade failed
                    # that we saved in _save_mysql_state_before_upgrade();
                    # Note: this isn't checked for error because we are already in
                    # an error state and an error from this already generated a message.
                    _restore_mysql_state_from_before_upgrade( 'failed_version' => $version_to_install, 'original_version' => $current_version );

                    return _mysql_upgrade_error( Cpanel::Exception::get_string($err), $conf );
                }

                # This iteration of the upgrade
                # was successful so we reset the
                # $current_version to the the version
                # we just installed.
                $current_version = $version_to_install;
            }

            return _finish_successful_upgrade($conf);
        }
    );

    if ( !$run || $run->had_error() ) {
        return _mysql_upgrade_error( $run->exception() || $run->autopsy(), $conf );
    }
    else {

        # We may have just restarted again here
        if ( _wait_for_mysql_to_come_online() ) {

            my $workarounds = [
                qw/
                  disable_password_validation_plugin
                  populate_mariadb_password_column
                  enable_maria_systemd_service
                  fix_mariadb_last_changed_password
                  /
            ];

            foreach my $wa (@$workarounds) {

                try {
                    Whostmgr::Mysql::Workarounds->can($wa)->();
                }
                catch {
                    warn $_;
                };
            }
        }

        return $run->return()->[0];
    }
}

sub _wait_for_mysql_to_come_online {
    return Cpanel::MysqlUtils::Running::wait_for_mysql_to_come_online(30);
}

# Disable service checks of mySQL / MariaDB
sub suspend_chksrvd_monitoring {

    Cpanel::Chkservd::Tiny::suspend_service( 'mysql' => CHKSRVD_SUSPEND_TIMEOUT );

    return;
}

# Resume service checks of mySQL / MariaDB
sub unsuspend_chksrvd_monitoring {

    Cpanel::Chkservd::Tiny::resume_service('mysql');

    return;
}

sub _mysql_upgrade_error {
    my ( $check_error, $conf ) = @_;
    get_output_obj()->error($check_error);
    stop_step( $STEP_MYSQL_UPGRADE, $MYSQL_UPGRADE_FAILED_ERROR_CODE, $conf );
    return {
        'error_code'    => $MYSQL_UPGRADE_FAILED_ERROR_CODE,
        'status'        => 0,
        'error_message' => $check_error
    };
}

sub get_configured_mysql_version {

    my $default_version = Cpanel::OS::mysql_default_version();
    my $cpconf          = Cpanel::Config::LoadCpConf::loadcpconf();

    return $default_version unless ref $cpconf;

    my $cpconf_version = $cpconf->{'mysql-version'};

    if ( !$cpconf_version ) {
        return $default_version;
    }

    return $cpconf_version;
}

sub is_mysql_unmanaged {
    Cpanel::LoadModule::load_perl_module('Cpanel::RPM::Versions::File');
    my $configured   = get_configured_mysql_version();
    my @versions     = grep { $_ >= $configured } Cpanel::MysqlUtils::Versions::get_versions();
    my $versions     = Cpanel::RPM::Versions::File->new( { 'only_targets' => [ Cpanel::MysqlUtils::Versions::get_rpm_target_names(@versions) ] } );
    my $in_unmanaged = $versions->list_rpms_in_state('unmanaged');
    return 1 if scalar keys %$in_unmanaged;

    my $local_rpm_versions = Cpanel::RPM::Versions::Directory->new()->{'local_file_data'};
    foreach my $mysql_version ( Cpanel::MysqlUtils::Versions::get_versions() ) {
        my ($key) = Cpanel::MysqlUtils::Versions::get_rpm_target_names($mysql_version);
        my $val = $local_rpm_versions->fetch( { 'section' => 'target_settings', 'key' => $key } );
        return 1 if $val && $val eq 'installed';
    }

    return 0;
}

sub set_mysql_version {
    my $new_version = shift;

    die "$new_version is not a valid MySQL or MariaDB version." unless ( $new_version && grep { $_ eq $new_version } Cpanel::MysqlUtils::Versions::get_versions() );

    my $cpconf_guard = Cpanel::Config::CpConfGuard->new();
    $cpconf_guard->{'data'}->{'mysql-version'} = $new_version;
    return $cpconf_guard->save();
}

###########################################################################
#
# Method:
#   unattended_upgrade
#
# Description:
#   Perform an unattened mysql upgrade,
#   and returns the status code
#
# Parameters:
#   See upgrade_mysql_with_status
#
# Returns:
#   0 if the upgrade succeeded
#
#   On failure it returns one of these error codes:
#    <child process died from a signal>    = -1;
#    $MYSQL_UPGRADE_FAILED_ERROR_CODE      = 4;
sub unattended_upgrade {
    my $conf = shift;

    $current_log ||= 'unattended_upgrade';

    my $child_proc = Cpanel::ForkSync->new( \&_run_unattended_upgrade, $conf );
    if ( $child_proc->signal_code() ) {

        # Signal report
        get_output_obj()->error( $child_proc->autopsy() );

        return -1;
    }

    # The return code here is different than the others
    # It indicates which step failed (if any) so that the retry button
    # will know which step to start at.
    my $step_failed = $child_proc->return()->[0];

    remove_progress_info() if !$step_failed;

    return $step_failed;
}
###########################################################################
#
# Method:
#   unattended_background_upgrade
#
# Description:
#   Perform an unattened mysql upgrade in the background,
#   and returns the status code
#
# Parameters:
#   See upgrade_mysql_with_status
#
# Returns:
#   0 if the upgrade succeeded
#
#   On failure it returns one of these error codes:
#    <child process died from a signal>    = -1;
#    $MYSQL_UPGRADE_FAILED_ERROR_CODE      = 4;
#
#   ...or, it can also throw exceptions. You need to accommodate both.
#
sub unattended_background_upgrade {
    my $conf = shift;

    $current_log ||= 'unattended_background_upgrade';
    _validate_conf($conf);
    my $time_id = _get_time_id();
    my $logid   = 'mysql_upgrade.' . $time_id;
    my $logdir  = _get_logdir();

    _ensure_logdir();

    my $result_file = "$logdir/$current_log.result";

    Cpanel::FileUtils::Write::overwrite( $result_file, '', 0600 );

    my $mysqlchildpid = Cpanel::ForkAsync::do_in_child(
        sub {

            Cpanel::CloseFDs::fast_daemonclosefds( $output_objs{$current_log} ? ( except => [ @{ $output_objs{$current_log} }{qw( error_log_fh human_readable_log_fh output_log_fh )} ] ) : () );
            my $output_obj = get_output_obj();
            open( STDERR, '>>&', $output_obj->{'error_log_fh'} ) or do {
                require Cpanel::Debug;
                Cpanel::Debug::log_warn("Could not redirect STDERR for '$logid': $!");
            };
            open( STDOUT, '>>&', $output_obj->{'human_readable_log_fh'} ) or do {
                require Cpanel::Debug;
                Cpanel::Debug::log_warn("Could not redirect STDOUT for '$logid': $!");
            };
            my $step_failed = _run_unattended_upgrade($conf);
            Cpanel::FileUtils::Write::overwrite( $result_file, $step_failed, 0600 );
            remove_progress_info() if !$step_failed;
        }
    );

    return $logid;
}

sub _run_unattended_upgrade {
    my ($conf) = @_;

    # We'll group all the upgrade logic here wrapped in a single subprocess.
    # This doesn't look as nice as running each upgrade step in sequence in a template,
    # but it will make it easier to deal with the admin closing the browser before the
    # upgrade has run to completion
    start_step( $STEP_MYSQL_UPGRADE, $conf );

    _setup_install_env();

    my $selected_version_product_name = Cpanel::MariaDB::version_is_mariadb( $conf->{'selected_version'} ) ? 'MariaDB' : 'MySQL';

    get_output_obj()->out("Beginning “$selected_version_product_name $conf->{'selected_version'}” upgrade...");

    my $upgrade_results = upgrade_mysql_with_status($conf);

    if ( ref $upgrade_results ne 'HASH' ) {
        get_output_obj()->error("$selected_version_product_name upgrade failed: $upgrade_results");
        return $MYSQL_UPGRADE_FAILED_ERROR_CODE;
    }
    elsif ( $upgrade_results->{'status'} ) {
        get_output_obj()->success("$selected_version_product_name upgrade completed successfully");
    }
    else {
        return $upgrade_results->{'error_code'};
    }

    get_output_obj()->out("------------------------------------");

    return $SUCCESS_ERROR_CODE;
}

sub start_step {
    my ( $step_number, $conf ) = @_;

    return _write_step(
        {
            'step'       => $step_number,
            'time_id'    => $time_id,
            'error_code' => 0,
            'status'     => -1
        },
        $conf
    );
}

sub _write_step {
    my ( $optsref, $conf ) = @_;

    _validate_conf( $conf, $optsref->{'error_code'} );

    my %stored_values = (
        'pid'              => $$,
        'selected_version' => $conf->{'selected_version'} || '',
        'upgrade_type'     => $conf->{'upgrade_type'},
        %{$optsref},
    );

    return Cpanel::DataStore::store_ref( $step_counter_file, \%stored_values );
}

sub stop_step {
    my ( $step_number, $error_code, $conf ) = @_;

    if ( $step_number == $STEP_FINISHED && !$error_code ) {
        remove_progress_info();
        return;
    }

    return _write_step(
        {
            'step'       => $step_number,
            'error_code' => $error_code,
            'status'     => $error_code ? 0 : 1,
        },
        $conf
    );
}

sub _validate_conf {
    my ( $conf, $error_code ) = @_;

    my $current_version = length $conf->{'current_version'} ? $conf->{'current_version'} : get_current_version( get_output_obj() );

    if ( !$current_version ) {
        my $err = "The system could not determine the currently installed version.";
        get_output_obj()->error($err);
        die $err;
    }

    my @valid_upgrade_types = (qw(interactive unattended_manual unattended_automatic));
    if ( defined $conf->{'upgrade_type'} && !grep { $_ eq $conf->{'upgrade_type'} } @valid_upgrade_types ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be one of the following values: [list_and_quoted,_2]', [ 'upgrade_type', \@valid_upgrade_types ] );
    }
    my @get_installable_versions = Cpanel::MysqlUtils::Versions::get_installable_versions_for_version($current_version);

    if ( defined $conf->{'selected_version'} && !grep { $_ eq $conf->{'selected_version'} } @get_installable_versions ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be one of the following values: [list_and_quoted,_2]', [ 'selected_version', \@get_installable_versions ] );
    }

    if ( !length $error_code || $error_code != $SUCCESS_ERROR_CODE ) {
        _update_conf_with_current_version_and_check_for_blockers($conf);
    }

    return 1;
}

sub get_progress_info {
    if ( -e $step_counter_file ) {
        my $ref = Cpanel::DataStore::fetch_ref($step_counter_file);

        # Ensure that stored step never exceeds the currently defined last step (old/modified counter file?)
        if ( exists $ref->{'step'} && $ref->{'step'} > $STEP_FINISHED ) {
            $ref->{'step'} = $STEP_FINISHED;
        }
        return $ref;
    }
    return;
}

sub remove_progress_info {
    unlink $step_counter_file;
    return;
}

sub _remove_install_mysql_bench_packages {
    my @bench_pkgs = _get_mysql_bench_packages() or return;
    Cpanel::Pkgr::remove_packages_nodeps(@bench_pkgs);
    return;
}

sub _get_mysql_bench_packages {
    my $pkg_version = Cpanel::Pkgr::installed_packages();
    my @packages    = grep { /^mysql-bench\b/i } sort keys %$pkg_version;
    return @packages;
}

{

    # How is this different then livesaferun?
    sub run_command_formatted {
        my ( $program, @args ) = @_;

        my $output_obj       = get_output_obj();
        my $callback_obj     = Cpanel::Parser::Callback->new( 'callback' => sub { $output_obj->out(@_); } );
        my $callback_err_obj = Cpanel::Parser::Callback->new( 'callback' => sub { $output_obj->error(@_); } );
        my $result           = Cpanel::SafeRun::Object->new(
            'program' => $program,
            'args'    => \@args,
            'stdout'  => Cpanel::CPAN::IO::Callback::Write->new( sub { return $callback_obj->process_data(@_); } ),
            'stderr'  => Cpanel::CPAN::IO::Callback::Write->new( sub { return $callback_err_obj->process_data(@_); } )
        );
        $callback_obj->finish();
        $callback_err_obj->finish();
        $output_obj->error( $result->autopsy() ) if $result->CHILD_ERROR();

        return $result;
    }

    sub get_output_obj {
        if ( !$current_log ) {
            require Cpanel::Carp;
            die Cpanel::Carp::safe_longmess("Cannot get_output_obj when current_log is not set");
        }
        if ( $output_objs{$current_log} ) {
            $Cpanel::SysPkgs::OUTPUT_OBJ_SINGLETON = $output_objs{$current_log};    # Legacy for EasyApache
            return $output_objs{$current_log};
        }

        my ( $human_readable_log_fh, $output_log_fh, $error_log_fh ) = _get_log_fhs();

        my $output_objs = [
            Cpanel::Output::Formatted::Terminal->new( 'filehandle' => $human_readable_log_fh ),    #
            Cpanel::Output->new( 'filehandle' => $output_log_fh )                                  #
        ];
        if ( Whostmgr::HTMLInterface::Output::output_html() ) {
            unshift @$output_objs, Cpanel::Output::Formatted::HTML->new( 'filehandle' => \*STDOUT );
        }
        $output_objs{$current_log} = Cpanel::Output::Multi->new(
            'output_objs' => $output_objs,
        );

        my $logdir = $LOG_BASE_DIR . '/mysql_upgrade.' . $time_id;
        $output_objs{$current_log}->out("Starting process with log file at $logdir/$current_log.log");
        $output_objs{$current_log}{'error_log_fh'}          = $error_log_fh;
        $output_objs{$current_log}{'human_readable_log_fh'} = $human_readable_log_fh;
        $output_objs{$current_log}{'output_log_fh'}         = $output_log_fh;

        $Cpanel::SysPkgs::OUTPUT_OBJ_SINGLETON = $output_objs{$current_log};    # Legacy for EasyApache

        return $output_objs{$current_log};
    }

    sub _ensure_logdir {
        my $logdir = _get_logdir();
        if ( !( -d $logdir || Cpanel::SafeDir::MK::safemkdir($logdir) ) ) {
            warn "Warning: Unable to access log dir “$logdir ” - $!";
        }

        return 1;
    }

    sub _get_logdir {
        my $time_id = _get_time_id();
        return $LOG_BASE_DIR . '/mysql_upgrade.' . $time_id;
    }

    sub _get_log_fhs {
        my ( $human_readable_log_fh, $output_log_fh, $error_log_fh );

        _ensure_logdir();

        my $logdir                       = _get_logdir();
        my $error_log_file_name          = $current_log . '.error';
        my $output_log_file_name         = $current_log . '.output';
        my $human_readable_log_file_name = $current_log . '.log';

        my $human_readable_logfile = $logdir . '/' . $human_readable_log_file_name;
        my $output_logfile         = $logdir . '/' . $output_log_file_name;
        my $error_logfile          = $logdir . '/' . $error_log_file_name;
        Cpanel::FileUtils::Open::sysopen_with_real_perms( $human_readable_log_fh, $human_readable_logfile, 'O_WRONLY|O_CREAT', 0600 ) or die "Unable to open log file “$human_readable_logfile” - $!";
        Cpanel::FileUtils::Open::sysopen_with_real_perms( $output_log_fh,         $output_logfile,         'O_WRONLY|O_CREAT', 0600 ) or die "Unable to open log file “$output_logfile” - $!";
        Cpanel::FileUtils::Open::sysopen_with_real_perms( $error_log_fh,          $error_logfile,          'O_WRONLY|O_CREAT', 0600 ) or die "Unable to open log file “$error_logfile” - $!";

        return ( $human_readable_log_fh, $output_log_fh, $error_log_fh );
    }

    sub _get_time_id {
        return $time_id if $time_id;
        my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) = localtime();
        $year += 1900;
        $mon  += 1;
        $time_id = sprintf(
            "%04d%02d%02d-%02d%02d%02d",
            $year, $mon, $mday, $hour, $min, $sec
        );
        return $time_id;

    }

}

sub _restore_mysql_state_from_before_upgrade {
    my (%OPTS) = @_;

    my $failed_version   = $OPTS{'failed_version'};
    my $original_version = $OPTS{'original_version'};

    my $has_error            = 0;
    my $saved_mysql_cnf_file = "$Cpanel::ConfigFiles::MYSQL_CNF.mysqlup.$original_version";
    if ( !rename( $saved_mysql_cnf_file, $Cpanel::ConfigFiles::MYSQL_CNF ) ) {
        get_output_obj()->error("Failed to restore the original configuration file from “$saved_mysql_cnf_file ” to “$Cpanel::ConfigFiles::MYSQL_CNF”.");
        $has_error = 1;
    }

    Cpanel::MysqlUtils::MyCnf::Migrate::enable_innodb_file_per_table();

    set_mysql_version($original_version);

    _resume_mysql_service();

    return $has_error;
}

sub _save_mysql_state_before_upgrade {
    my (%OPTS) = @_;

    my $new_version     = $OPTS{'new_version'};
    my $current_version = $OPTS{'current_version'};

    #
    # Make sure that /etc/my.cnf is newer than the one that
    # comes in the rpm to avoid it getting overwritten
    #
    Cpanel::FileUtils::TouchFile::touchfile($Cpanel::ConfigFiles::MYSQL_CNF);

    suspend_chksrvd_monitoring();

    my $saved_mysql_cnf_file = "$Cpanel::ConfigFiles::MYSQL_CNF.mysqlup.$current_version";

    # We used to move my.cnf out of the way, now we just make a copy of it
    # as we want mysql to startup with options we need
    Cpanel::SafeRun::Errors::saferunnoerror( '/bin/cp', '-f', '--', $Cpanel::ConfigFiles::MYSQL_CNF, $saved_mysql_cnf_file );
    if ($?) {
        get_output_obj()->error("Failed to rename “$Cpanel::ConfigFiles::MYSQL_CNF” to “$saved_mysql_cnf_file” because of an error: $!.");
        return 0;
    }

    return 1;
}

sub _resume_mysql_service {
    get_output_obj()->out("Restarting mysql service.");
    get_output_obj()->out( Cpanel::Services::Restart::restartservice('mysql') );

    if ( _wait_for_mysql_to_come_online() ) {

        # If we fail to come online we will warn. Hopefully
        # chkservd will be able to fix it later or at least get
        # the admin's attention in the event this is an automated upgrade

        unsuspend_chksrvd_monitoring();
    }

    return 1;
}

sub _finish_successful_upgrade {
    my ($conf) = @_;

    _resume_mysql_service();

    # The upgrade was successful, and this is the last "step" of the process.
    # So lets remove the progress state file.
    remove_progress_info();

    #Run the check to ensure that, if this is a MariaDB upgrade > 10.0, that the systemd.tmpfs file for
    #for creating the directory for the MariaDB pidfile exists
    _comment_out_pidFile_in_myCnf_for_mariadb_gt_10_0();

    return {
        'error_code'    => $SUCCESS_ERROR_CODE,
        'status'        => 1,
        'error_message' => 'OK',
    };
}

sub _setup_install_env {
    Cpanel::Sys::Setsid::Fast::fast_setsid();
    Cpanel::Rlimit::set_rlimit_to_infinity();

    # Preserve GATEWAY_INTERFACE for Whostmgr::HTMLInterface::Output
    my $gateway_interface = $ENV{'GATEWAY_INTERFACE'};
    Cpanel::Env::clean_env( 'http_purge' => 1 );
    $ENV{'GATEWAY_INTERFACE'} = $gateway_interface;
    return 1;
}

sub _show_mysql_startup_log {
    return Cpanel::Services::Log::Display->new( 'service' => 'mysql', 'output_obj' => get_output_obj() )->show_startup_log();
}

sub _install_mysql_version ( $version_to_install, $is_reinstall ) {

    my $main_pid                        = $$;
    my $maintain_chkservd_suspended_pid = Cpanel::ForkAsync::do_in_child(
        sub {
            local $0 = q[mysql upgrade - chkservd suspend_service];
            while ( -e "/proc/${main_pid}/status" ) {

                # extend the chksrvd suspend time in background
                suspend_chksrvd_monitoring();
                sleep REFRESH_CHKSRVD_SUSPEND_TIMEOUT;
            }

            return;    # exit here
        }
    );

    my $on_exit = Cpanel::Finally->new(
        sub {
            return Cpanel::Kill::Single::safekill_single_pid($maintain_chkservd_suspended_pid);
        }
    );

    return __install_mysql_version( $version_to_install, $is_reinstall );
}

sub __install_mysql_version ( $version_to_install, $is_reinstall ) {

    my $version_to_install_product_name = Cpanel::MysqlUtils::Versions::get_vendor_for_version($version_to_install);

    my $installer_obj;
    if ( $version_to_install_product_name ne 'Mysql-legacy' ) {
        my $module = "Cpanel::${version_to_install_product_name}::Install";
        Cpanel::LoadModule::load_perl_module($module);
        $installer_obj = $module->new( 'output_obj' => get_output_obj() );
    }

    if ($installer_obj) {
        $installer_obj->ensure_installer_can_use_repo($version_to_install);
        $installer_obj->install_known_deps($version_to_install);
    }

    set_mysql_version($version_to_install);

    my $ensure_ok;
    if ($installer_obj) {
        get_output_obj()->out("Ensuring $version_to_install_product_name packages for version “$version_to_install”.");

        # CPANEL-39190: Pre-seeding breaks reinstalls, but there's no reason to
        # have to pass that info to the installer, so this code needs to live
        # here instead of in Cpanel::Repo::Install::MysqlBasedDB::install_rpms().
        #
        my $mysql_on_ubuntu = Cpanel::OS::db_needs_preseed() && !Cpanel::MariaDB::version_is_mariadb($version_to_install);
        if ( $mysql_on_ubuntu && !$is_reinstall ) {

            # Use debconf to configure the stuff it would otherwise prompt for before we actually install the packages
            # This will cover both the version of mysql for the "mysql-apt-config" package and other options for the "mysql-community-server" package
            my $preseed_path = $installer_obj->write_preseed_file($version_to_install);
            $installer_obj->preseed_configuration($preseed_path);
        }

        #_ensure_mariadb_is_installable_if_needed created $installer_obj
        $ensure_ok = $installer_obj->install_rpms($version_to_install);
    }
    else {
        get_output_obj()->out("Ensuring MySQL packages for version “$version_to_install”.");

        Cpanel::LoadModule::load_perl_module('Cpanel::MysqlUtils::Install');

        $ensure_ok = 'Cpanel::MysqlUtils::Install'->new( output_obj => get_output_obj() )->ensure_rpms();
    }

    if ( !$ensure_ok ) {
        die "Could not upgrade to “$version_to_install_product_name $version_to_install”";
    }

    # Wait for mysql to start up after the install
    if ( _wait_for_mysql_to_come_online() == 0 ) {
        get_output_obj()->error("The system could not start $version_to_install_product_name $version_to_install");
        _show_mysql_startup_log();
        die "$version_to_install_product_name did not start up after upgrade; there may be a problem in $Cpanel::ConfigFiles::MYSQL_CNF.";
    }

    my $running_version = Cpanel::MysqlUtils::Version::uncached_mysqlversion();
    if ( !$running_version ) {

        # under certain conditions, check_cpanel_pkgs could end up
        # removing mysql and not installing a new version, leaving
        # you with no mysql, or under error conditions not caught
        # above, you could end up with the original version of mysql
        # and not the version you intended to install.  This will
        # check to see if you got what you wanted.
        die "$version_to_install_product_name removed: did not upgrade to $version_to_install.";
    }
    elsif ( $running_version ne $version_to_install ) {
        die "We expected to upgrade to $version_to_install; however, the system is currently on version $running_version.";
    }

    # Install the relevant hook
    $installer_obj->install_upgrade_hook() if $installer_obj;

    return 1;
}

# more aptly named get_latest_installable_version
sub get_latest_available_version {
    my %opts = @_;

    my $versions = $opts{'version'} ? Cpanel::MysqlUtils::Versions::get_upgrade_targets( $opts{'version'} ) : get_available_versions();

    my @versions_to_check = @{$versions};

    my $unsupported_versions = Cpanel::OS::unsupported_db_versions();

    while ( my $latest = pop @versions_to_check ) {
        next if grep { $_ eq $latest } @$unsupported_versions;
        return $latest;
    }

    # Nothing to upgrade to.
    return;
}

# more aptly named get_installable_versions
sub get_available_versions {
    Cpanel::LoadModule::load_perl_module('Cpanel::RPM::Versions::Directory');

    # Get only the values from the local.versions file.
    my $local_rpm_versions = Cpanel::RPM::Versions::Directory->new()->{'local_file_data'};

    my @available_versions;

    foreach my $mysql_version ( Cpanel::MysqlUtils::Versions::get_versions() ) {
        my ($key) = Cpanel::MysqlUtils::Versions::get_rpm_target_names($mysql_version);

        # If the target is set to "uninstalled" we cannot upgrade to this version
        # (or any later version).
        my $val = $local_rpm_versions->fetch( { 'section' => 'target_settings', 'key' => $key } );

        if ( defined $val ) {

            # the client marked the rpm to be uninstalled, so we cannot install it
            next if $val eq "uninstalled";

            # the client does not want cPanel to manage installations
            last if $val eq "unmanaged";
        }

        push @available_versions, $mysql_version;
    }

    return \@available_versions;
}

sub get_version_metadata {

    my @targets = qw/
      item_short_version
      recommended_version
      selected_version
      locale_version
      eol_time
      release_notes
      features
      experimental
      /;

    require Cpanel::Database;
    my $dbs = Cpanel::Database->new_all_supported();

    my $metadata = [];

    for my $db (@$dbs) {
        my $data;
        foreach my $target (@targets) {
            $data->{$target} = $db->$target;
            if ( $target eq 'item_short_version' ) {
                $data->{item_short_version_cmp} = $data->{item_short_version} =~ s/\.//r;
            }
        }
        push( @$metadata, $data );
    }
    @$metadata = sort { $b->{item_short_version_cmp} <=> $a->{item_short_version_cmp} } @$metadata;

    return $metadata;
}

sub get_current_version ( $output_obj = undef ) {

    # handy helpers for logging
    my $log_info = ref $output_obj ? sub ($s) { $output_obj->out($s);  return } : sub ($s) { return };
    my $log_warn = ref $output_obj ? sub ($s) { $output_obj->warn($s); return } : sub ($s) { warn($s); return };

    my ( $version, $err );

    # 1. try to get the version based connecting to the server
    try {
        if ( $version = Cpanel::MysqlUtils::Version::uncached_mysqlversion() ) {
            $log_info->("Obtained version information from system.");
        }
    }
    catch {
        $err = $_;
        $log_warn->("Failed to get MySQL version from server: $err");
    };
    return $version if $version;

    # 2. try to get the guess version from local data files
    try {
        if ( $version = Cpanel::MysqlUtils::Version::get_short_mysql_version_from_data_files() ) {
            $log_info->("Obtained version information from mysql data files.");
        }
    }
    catch {
        $err = $_;
        $log_warn->("Failed to guess MySQL version from data files: $err");
    };
    return $version if $version;

    # 3. try to get the MySQL version from configured version
    try {
        if ( $version = get_configured_mysql_version() ) {
            $log_info->("Obtained version information from cpanel.config.");
        }
    }
    catch {
        $err = $_;
        $log_warn->("Failed to get configured MySQL version: $err");
    };
    return $version if $version;

    # last. Fallback to default
    $version = $Cpanel::MysqlUtils::Version::DEFAULT_MYSQL_RELEASE_TO_ASSUME_IS_INSTALLED;
    $log_warn->("Defaulted to mysql version $version");

    return $version;
}

sub _update_conf_with_current_version_and_check_for_blockers {
    my ($conf) = @_;

    my $selected_version = $conf->{'selected_version'};

    #We check for missing “selected_version” elsewhere; thus,
    #if this value isn’t here, we just skip the further validation
    #in deference to what will bug out later on.
    if ($selected_version) {
        local $current_log = $current_log || 'preflight_check';

        # Its possible something restarted mysql so be sure to wait here
        # before checking
        _wait_for_mysql_to_come_online();

        #Likewise, we check for missing current version elsewhere.
        my $current_version = get_current_version( get_output_obj() ) or return;
        $conf->{'current_version'} = $current_version;

        require Whostmgr::Mysql::Upgrade::Warnings;
        require Cpanel::StringFunc::HTML;

        my ( $fatal, $warnings_ar ) = Whostmgr::Mysql::Upgrade::Warnings::get_upgrade_warnings( $selected_version, $current_version );
        my $warnings_str = "\n" . join(
            '   ',
            map {
                my $msg = $_->{'message'};
                chomp($msg);
                $msg .= "\n";
                Cpanel::StringFunc::HTML::trim_html( \$msg );
                "$_->{'severity'}: $msg"
            } @$warnings_ar
        );
        if ($fatal) {
            die Cpanel::Exception->create( "The system cannot upgrade your version of [asis,MySQL] or [asis,MariaDB] because of at least one impediment: [_1]", [$warnings_str] );
        }
        elsif (@$warnings_ar) {
            get_output_obj()->warn("Proceeding with MySQL/MariaDB upgrade despite the following: $warnings_str");
        }
    }

    return;
}

# for tests
sub _close_output_objs {
    undef %output_objs;
    return;
}

#systemd-tmpfiles.d workaround for MariaDB bug MDEV-15543 installs /usr/lib/tmpfiles.d/mysqld.conf
#with an incorrect path. If the above bug is ever fixed, this can be retested and probably removed
sub _comment_out_pidFile_in_myCnf_for_mariadb_gt_10_0 {

    #should only run on systems with systemd and MariaDB > 10.0
    if ( Cpanel::OS::is_systemd() && Cpanel::MariaDB::version_is_mariadb( get_current_version() ) ) {
        require Cpanel::MysqlUtils::MyCnf::Modify;
        Cpanel::MysqlUtils::MyCnf::Modify::modify(
            sub {
                my ( $section, $key, $value ) = @_;
                if ( $key eq 'pid-file' ) {
                    return [ 'COMMENT', $key, $value ];
                }
            }
        );
    }
    return;
}
1;
