package Whostmgr::API::1::Mysql;

# cpanel - Whostmgr/API/1/Mysql.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Validate::FilesystemNodeName ();
use Cpanel::LoadFile                     ();
use Cpanel::Exception                    ();
use Cpanel::MysqlUtils::Versions         ();
use Cpanel::MariaDB                      ();
use Cpanel::OS                           ();
use Cpanel::ConfigFiles                  ();
use Cpanel::UTF8::Deep                   ();

use Try::Tiny;

use constant NEEDS_ROLE => 'MySQLClient';

sub _make_version_record {
    my ($version) = @_;

    return {
        'version' => $version,
        'server'  => ( Cpanel::MariaDB::version_is_mariadb($version) ? 'mariadb' : 'mysql' ),
    };
}

sub _restore_mycnf_and_set_metadata ( $content, $reason, $metadata ) {
    $metadata->{result} = 0;
    my $ret = Cpanel::MysqlUtils::MyCnf::SQLConfig::save_mycnf($content);
    $reason .= ' No changes were made to the sql configuration.' if $ret;
    $metadata->{reason} = $reason;
    return 1;
}

sub update_sql_config ( $args, $metadata, @ ) {

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'data' ] ) if !$args->{'data'};
    my $data = $args->{'data'};

    my $to_modify = {};
    my $to_remove = {};

    for my $hr (@$data) {
        my $section = $hr->{section};
        my $target  = $hr->{remove} ? $to_remove : $to_modify;
        $hr->{value} //= '';

        for ( $hr->{name}, $hr->{value} ) {

            my $utf_copy = Cpanel::UTF8::Deep::decode_clone($_);

            #match any non-printable character.
            if ( $utf_copy =~ /[^[:print:]]/u ) {
                $metadata->{result} = 0;
                $metadata->{reason} = "No changes were made due to the following containing non-printable characters: $_";
                return { status => 0 };
            }
        }

        # Special handling for sql_mode when it has no value.
        # sql_mode with no value will render the database unable to start.
        # setting it equal to an empty string is what people actually want to do.
        $hr->{value} = "''" if $hr->{name} eq 'sql_mode' && $hr->{value} eq '';

        # Special handling for innodb_buffer_pool_size.
        # There is a tweak setting that will overwrite the value of innodb_buffer_pool_size.
        # This tweak setting is no longer needed, and did not work as intended anyways. It is
        # scheduled to be removed in BOO-2022. For now, we will disable it if the user chooses to
        # modify this setting. This can be removed as part of BOO-2022.
        if ( $hr->{name} eq 'innodb_buffer_pool_size' ) {
            require Whostmgr::TweakSettings::Configure::Main;
            my $tweak_main = Whostmgr::TweakSettings::Configure::Main->new();
            my $conf       = $tweak_main->get_conf();
            if ( $conf->{'mycnf_auto_adjust_innodb_buffer_pool_size'} ) {
                $tweak_main->set( 'mycnf_auto_adjust_innodb_buffer_pool_size', 0 );
                $tweak_main->save();
            }
        }

        push( @{ $target->{$section} }, { $hr->{name} => $hr->{value} } );
    }

    require Cpanel::MysqlUtils::MyCnf::SQLConfig;

    my $original_mycnf = Cpanel::MysqlUtils::MyCnf::SQLConfig::get_mycnf();

    my $modify_status = Cpanel::MysqlUtils::MyCnf::SQLConfig::process_mycnf_changes($to_modify);
    if ( !$modify_status ) {
        _restore_mycnf_and_set_metadata( $original_mycnf, 'Failed to modify the database configuration.', $metadata );
        return { status => 0 };
    }

    my $remove_status = Cpanel::MysqlUtils::MyCnf::SQLConfig::process_mycnf_changes( $to_remove, { remove => 1 } );
    if ( !$remove_status ) {
        _restore_mycnf_and_set_metadata( $original_mycnf, 'Failed to modify the database configuration.', $metadata );
        return { status => 0 };
    }

    # check the new config and comment out anything invalid, just in case...
    require Cpanel::MysqlUtils::MyCnf::Migrate;
    my $invalid_keys_found = Cpanel::MysqlUtils::MyCnf::Migrate::scrub_invalid_values($Cpanel::ConfigFiles::MYSQL_CNF);
    if ($invalid_keys_found) {
        my $reason = "Found invalid options in my.cnf: " . join( ', ', @$invalid_keys_found ) . ".";
        _restore_mycnf_and_set_metadata( $original_mycnf, $reason, $metadata );
        return { status => 0 };
    }

    require Cpanel::ServiceManager::Services::Mysql;
    my $service = Cpanel::ServiceManager::Services::Mysql->new( restart_attempts => 1 );
    eval { $service->restart() };
    if ($@) {

        my $err = $@->can('to_string');
        my $msg;
        $msg = $err->($@) if $err;
        $msg //= 'Database failed to start.';
        $msg .= ' Restarting database with the original configuration.';
        _restore_mycnf_and_set_metadata( $original_mycnf, $msg, $metadata );

        {
            local $@;

            # If we *still* failed to restart, give up.
            eval { $service->restart() };
            if ($@) {
                $metadata->{reason} .= ' Database failed to start. Contact your system administrator.';
                return { status => 0 };
            }
        }

        $metadata->{reason} .= ' Database restarted successfully.';
        return { status => 0 };
    }

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
    return { status => 1 };
}

# NOTE: returns MySQL AND MariaDB versions
sub installable_mysql_versions {
    my ( $args, $metadata ) = @_;

    require Whostmgr::Mysql::Upgrade;
    my $current_version = Whostmgr::Mysql::Upgrade::get_current_version();

    my @installable_versions = Cpanel::MysqlUtils::Versions::get_installable_versions_for_version($current_version);

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
    return { 'versions' => [ map { _make_version_record($_) } @installable_versions ] };
}

sub current_mysql_version {
    my ( $args, $metadata ) = @_;

    require Whostmgr::Mysql::Upgrade;
    my $current_version = Whostmgr::Mysql::Upgrade::get_current_version();

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
    return _make_version_record($current_version);
}

# NOTE!! This name is a misnomer!
# this returns the latest *installable* version of MySQL *or* MariaDB
# per the API docs:
# "This function retrieves the latest available version of MySQL® or MariaDB®."
sub latest_available_mysql_version {
    my ( $args, $metadata ) = @_;

    require Cpanel::MysqlUtils::Version;
    my $version = Cpanel::MysqlUtils::Version::mysqlversion();
    require Whostmgr::Mysql::Upgrade;

    my $latest_available_version = Whostmgr::Mysql::Upgrade::get_latest_available_version( 'version' => $version );

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
    return _make_version_record($latest_available_version);
}

sub start_background_mysql_upgrade {
    my ( $args, $metadata ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'version' ] ) if !$args->{'version'};

    my $unsupported_versions = _get_unsupported_database_versions();

    if ( grep { $_ eq $args->{'version'} } @{$unsupported_versions} ) {
        die Cpanel::Exception::create( 'Database::DatabaseUnsupported', [ version => $args->{'version'}, os => Cpanel::OS::display_name() ] );
    }

    require Whostmgr::Mysql::Upgrade;
    my $upgrade_id = Whostmgr::Mysql::Upgrade::unattended_background_upgrade(
        {
            upgrade_type     => 'unattended_manual',
            selected_version => $args->{'version'}
        }
    );

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
    return { upgrade_id => $upgrade_id };
}

sub background_mysql_upgrade_status {
    my ( $args, $metadata ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ 'name' => 'upgrade_id' ] ) if !$args->{'upgrade_id'};
    Cpanel::Validate::FilesystemNodeName::validate_or_die( $args->{'upgrade_id'} );

    require Whostmgr::Mysql::Upgrade;
    my $error          = $Whostmgr::Mysql::Upgrade::FAILURE_ERROR_CODE;
    my $state          = 'unknown';
    my $log_path       = $Whostmgr::Mysql::Upgrade::LOG_BASE_DIR . '/' . $args->{'upgrade_id'};
    my $result_file    = "$log_path/unattended_background_upgrade.result";
    my $log_file       = "$log_path/unattended_background_upgrade.log";
    my $error_log_file = "$log_path/unattended_background_upgrade.error";
    my $progress       = Whostmgr::Mysql::Upgrade::get_progress_info();
    my $log            = Cpanel::LoadFile::load($log_file);
    my $error_log      = Cpanel::LoadFile::load($error_log_file);

    if ( ref $progress && $progress->{'pid'} && _is_pid_alive( $progress->{'pid'} ) ) {
        $error = 0;
        $state = 'inprogress';
    }
    else {    # only read the result file once the process stopped
        my $result_file_contents = Cpanel::LoadFile::load($result_file);
        if ( $result_file_contents eq '0' ) {
            $error = 0;
            $state = 'success';
        }
        else {
            $error = int( $result_file_contents || $error );
            $state = 'failed';
        }
    }

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
    return { 'error_log' => $error_log, 'log' => $log, 'state' => $state, 'error' => $error };
}

sub background_mysql_upgrade_checker_run {
    my ( $args, $metadata ) = @_;

    # NOTE: MySQL 5.7 or 8 repo being enabled *should* mean that mysql-shell
    # is already available. Other versions running this API would fail.
    require Cpanel::Pkgr;
    require Cpanel::ProcessLog::WithChildError;

    my $installed = Cpanel::Pkgr::get_package_version('mysql-shell') // 0;

    my $log_entry = Cpanel::ProcessLog::WithChildError->create_new( 'mysql_upgrade_checker', 'CHILD_ERROR' => '?' );

    require Cpanel::Daemonizer::Tiny;
    my $pid = Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            require Cpanel::Autodie;
            my $dir = "/var/cpanel/logs/${log_entry}";
            Cpanel::Autodie::open( my $fh, ">", "$dir/txt" );

            require Cpanel::SafeRun::Object;
            my $run_res;
            if ( !$installed ) {
                require Cpanel::SysPkgs;
                require Cpanel::OS;
                my $ok = Cpanel::SysPkgs->new()->install_packages( packages => [ Cpanel::OS::package_MySQL_Shell() ] );
                if ( !$ok ) {
                    Cpanel::ProcessLog::WithChildError->set_metadata( "${log_entry}", CHILD_ERROR => 1 );
                    exit 1;    ## no critic(Cpanel::NoExitsFromSubroutines) -- makes sense to exit from "daemon" if we get dirty output from command above
                }
            }

            # Run the upgrade check, print output to log.
            require Cpanel::MysqlUtils::MyCnf::Basic;
            my $password = Cpanel::MysqlUtils::MyCnf::Basic::getmydbpass('root');
            my $stdin    = "$password\nN\n";
            $run_res = Cpanel::SafeRun::Object->new(
                'program' => '/usr/bin/mysqlsh',
                'args'    => [qw{-- util check-for-server-upgrade { --user=root --host=localhost } --target-version=8.0.15 --config-path=/etc/my.cnf}],
                'stdin'   => $stdin,
                'stdout'  => $fh,
                'stderr'  => $fh,
            );
            my $exit_code = $run_res->error_code() || 0;
            Cpanel::ProcessLog::WithChildError->set_metadata( "${log_entry}", CHILD_ERROR => $exit_code );
            exit $exit_code;
        },
        $installed,
        $log_entry
    );

    @{$metadata}{ 'result', 'reason' } = ( 1, 'OK' );
    return { 'log_entry' => "${log_entry}", 'pid' => $pid };
}

sub _get_unsupported_database_versions {
    return Cpanel::OS::unsupported_db_versions();
}

# created for testability

sub _is_pid_alive {
    my ($pid) = @_;
    return kill( 0, $pid ) ? 1 : 0;
}

1;
