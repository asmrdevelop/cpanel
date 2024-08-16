package Cpanel::MysqlUtils::MyCnf::Adjust;

# cpanel - Cpanel/MysqlUtils/MyCnf/Adjust.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(RequireUseWarnings)

our $VERSION = '1.2';

use Try::Tiny;

use Cpanel::Autodie                 ();
use Cpanel::LoadFile                ();
use Cpanel::CachedCommand::Save     ();
use Cpanel::CachedCommand::Utils    ();
use Cpanel::ConfigFiles             ();
use Cpanel::Debug                   ();
use Cpanel::MysqlUtils::Compat      ();
use Cpanel::MysqlUtils::Connect     ();
use Cpanel::MysqlUtils::Running     ();
use Cpanel::MysqlUtils::MyCnf::Full ();
use Cpanel::MysqlUtils::Systemd     ();
use Cpanel::OS                      ();
use Cpanel::Exception               ();

use Cpanel::Services::Enabled     ();
use Cpanel::Sys::Hardware::Memory ();

use Cpanel::Config::LoadCpConf ();

our $DEFAULT_INTERVAL = 14400;                                              # 4 HOURS
our $INTERVAL_KEY     = 'Cpanel::MysqlUtils::MyCnf::Adjust::auto_adjust';

sub _istrue {
    my ($val) = @_;

    $val = uc($val);

    if (   $val == 1
        || $val eq "TRUE"
        || $val eq "YES"
        || $val eq "ON" ) {
        return 1;
    }

    return 0;
}

#
#  module_config keys
#     config_key  : name of the /var/cpanel/cpanel.config key
#     min         : minimum allowed value
#     max         : maximum allowed value
#     section     : section in my.cnf
#     setting     : setting in the section of the my.cnf
#     recommended : coderef that generates a recommendation based on local machine configuration
#
our $module_config = {
    'OpenFiles' => {
        'config_key'                => 'mycnf_auto_adjust_openfiles_limit',
        'set-noconfig-to-recommend' => 1,
        'min'                       => 2_048,                                 # default mysql value
        'max'                       => 80_000,
        'section'                   => 'mysqld',
        'setting'                   => 'open_files_limit',
        'systemd_section'           => 'Service',
        'systemd_setting'           => 'LimitNOFILE',
        'recommend'                 => sub {
            my $recommendation;

            try {
                # case 106345:
                # libmariadb has been patched to send
                # and receive with MSG_NOSIGNAL
                # thus avoiding the need to trap SIGPIPE
                # which can not be reliably
                # done in perl because perl will overwrite
                # a signal handler that was done outside
                # of perl and fail to restore a localized
                # one.

                my $dbh_connection = Cpanel::MysqlUtils::Connect->new();
                my $dbh            = $dbh_connection->{'dbh'};
                local $dbh->{'RaiseError'} = 1;

                my $row = $dbh->selectrow_arrayref("SELECT COUNT(*) FROM information_schema.tables;");

                $dbh->disconnect();

                #MySQL requires two file descriptors per MyISAM table.
                $recommendation = $row->[0] * 2;

                #Case 119669, this code can change by 1 or 2 for an account
                #transfer, which means it would restart on each transfer.
                #This is a simple stepping algorithm, it will always choose a
                #stepped Ceiling, causing it to change less often.

                my $step          = 1000;    # the default open files limit ends up at 10000 anyway
                my $practical_min = 40000;

                # this should ensure that the value is at least $step above
                # current and is stepping by $step.
                my $nval = int( ( $recommendation + $step ) / $step ) + 1;
                $recommendation = $nval * $step;
                if ( $recommendation < $practical_min ) {
                    $recommendation = $practical_min;
                }
            }
            catch {
                my $isRunning = Cpanel::MysqlUtils::Running::is_mysql_running();
                if ( !$isRunning ) {
                    Cpanel::Debug::log_warn("Adjust called while MySQL is not running, OpenFiles cannot be adjusted at this time") unless exists $ENV{'CPANEL_BASE_INSTALL'};
                }
                else {
                    Cpanel::Debug::log_warn( Cpanel::Exception::get_string($_) );
                }
            };

            return $recommendation;
        },
    },
    'MaxAllowedPacket' => {
        'config_key' => 'mycnf_auto_adjust_maxallowedpacket',
        'min'        => '16M',
        'max'        => '1G',
        'section'    => 'mysqld',
        'setting'    => 'max_allowed_packet',
        'recommend'  => sub { return '256M'; },
    },
    'InnodbBufferPoolSize' => {
        'config_key'                => 'mycnf_auto_adjust_innodb_buffer_pool_size',
        'set-noconfig-to-recommend' => 1,
        'min'                       => '8M',
        'max'                       => sub {

            # up to 80% of sys mem
            int( Cpanel::Sys::Hardware::Memory::get_installed() * 0.80 ) . "M";
        },
        'section' => 'mysqld',
        'setting' => 'innodb_buffer_pool_size',
        'skip_if' => sub {
            my ($local_mycnf) = @_;

            my $output = 0;

            my @skip = ( 'skip-innodb', 'skip_innodb' );
            foreach my $key (@skip) {
                if ( exists $local_mycnf->{'mysqld'}{$key} ) {
                    my $val = $local_mycnf->{'mysqld'}{$key};
                    if ( $val eq "" || _istrue($val) ) {
                        $output = 1;
                        last;
                    }
                }
            }

            if ( !$output ) {
                my $key = 'innodb';

                if ( exists $local_mycnf->{'mysqld'}{$key} ) {
                    my $val = $local_mycnf->{'mysqld'}{$key};
                    if ( $val ne "" && !_istrue($val) ) {
                        $output = 1;
                        last;
                    }
                }
            }

            return $output;
        },
        'recommend' => sub {

            # if we are before 5.1, recommended should be 8M which is the
            # default for the older versions.

            my $cpanel_conf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
            if ( $cpanel_conf->{'mysql-version'} < 5.1 ) { return "8M"; }

            # if sys mem is 512M or less, recommend 8M
            # if sys mem is 4G+ recommend 128M (the default)
            # in between proportional amounts

            my $sys_mem = Cpanel::Sys::Hardware::Memory::get_installed();

            if ( $sys_mem <= 512 ) {
                return "8M";
            }
            elsif ( $sys_mem >= 4096 ) {
                return "128M";
            }

            # y = mx + b, derived from 2 points (512, 8), (4096, 128).

            my $mem = int( ( 0.033482 * $sys_mem ) + -9.142857 );

            return $mem . "M";
        },
    }
};

sub _get_module_config {
    for my $hr ( values %$module_config ) {
        if ( 'CODE' eq ref $hr->{'max'} ) {
            $hr->{'max'} = $hr->{'max'}->();
        }
    }

    return $module_config;
}

###########################################################################
#
# Method:
#   auto_adjust
#
# Description:
#   This function automaticlly djusts my.cnf settings referenced in
#   $module_config to recommended values taking into account the
#   minimum specified values if passed.
#
# Parameters:
#   $config_input   - A hashref with the following possible keys:
#       force      - Ignore the cpanel.config key setting and always adjust all requested modules
#       verbose    - Log information messages
#       debug      - Log information messages but do not modify my.cnf
#       interval   - If specified auto_adjust will do nothing if it has already run inside the interval.
#       no-restart - Skip restarting MySQL if changes are made to my.cnf
#   $module_input   - A hashref with the following possible keys:
#       $module         - A hashref of keys for each module
#           min-value      - The minimum value that should be used to for the recommendation.
#                            This key is currently used by the restore system with the
#                            value of the remote machine to ensure the local machine
#                            has at least the same value or larger.
#
# Exceptions:
#   Cpanel::Exception::RestartFailed - Thrown if restarting MySQL fails.
#
# Returns:
#   The method returns the number of modified values.
#
sub auto_adjust {
    my ( $config_input, $module_input ) = @_;

    # Preserve the behavior from the
    # openfiles adjustment script:
    # Nothing to do if mysql is disabled
    return if !Cpanel::Services::Enabled::is_enabled('mysql');

    my $datastore_file = Cpanel::CachedCommand::Utils::_get_datastore_filename($INTERVAL_KEY);

    my $module_config = _get_module_config();

    # By default do them all
    $config_input ||= {};
    $module_input ||= { map { $_ => {} } keys %{$module_config} };

    my $runtime  = time();
    my $interval = $config_input->{'interval'};
    my $debug    = $config_input->{'debug'};
    my $verbose  = $config_input->{'verbose'} || $debug;
    if ($interval) {
        my $last_runtime = Cpanel::LoadFile::loadfile($datastore_file) || 0;
        my $change       = ( $runtime - $last_runtime );
        if ( $last_runtime && $last_runtime <= $runtime && $change < $interval ) {
            _note( $verbose, "auto_adjust was skipped because it already ran inside the specific interval of '$interval'" );
            return;
        }
    }

    my $force             = $config_input->{'force'};
    my $no_restart        = $config_input->{'no-restart'};
    my $is_systemd        = Cpanel::OS::is_systemd();
    my $cpanel_conf       = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    my $local_mycnf       = Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf();
    my $systemd_dropin_hr = _find_mariadb_or_mysql_file($is_systemd);
    my %config_settings   = ( local_mycnf_contents => $local_mycnf, module_input => $module_input );
    @config_settings{qw(systemd_dropin_contents systemd_dropin_file)} = @{$systemd_dropin_hr}{qw( contents path )};

    my ( $daemon_reload, $module_text ) = _remove_mysql_systemd_limits_file_if_needed($is_systemd);

    my @modules  = grep { _wanted( $_, $force, $cpanel_conf, $verbose ) } sort keys %{$module_input};
    my @modified = _update_modules( \@modules, $module_config, \%config_settings, { verbose => $verbose, debug => $debug, force => $force } );

    if ( @modified && !$no_restart ) {
        _note( 1, 'Restarting MySQL due to my.cnf modifications.' );
        _restart_mysql_for_modules( $is_systemd, [ sort map { $module_config->{$_}{'setting'} } @modified ] );
    }
    elsif ( $daemon_reload && !$no_restart ) {
        _note( 1, "auto_adjust restarting mysql due to removal of systemd limits.conf file" );
        _restart_mysql_for_modules( $is_systemd, [$module_text] );
    }

    Cpanel::CachedCommand::Save::store( 'name' => $INTERVAL_KEY, 'data' => $runtime );

    return scalar @modified;
}

sub _update_modules {
    my ( $modules, $module_config, $config_settings, $opts ) = @_;

    my ( $verbose, $debug ) = @{$opts}{qw( verbose debug )};

    my @modified;
    foreach my $module (@$modules) {
        my ( $section, $setting, $conf );

        # If we're supposed to have a systemd_dropin_file we should check that file, even if it doesn't exist yet
        if ( $config_settings->{systemd_dropin_file} && $module_config->{$module}->{'systemd_section'} ) {
            $section = $module_config->{$module}->{"systemd_section"};
            $setting = $module_config->{$module}->{"systemd_setting"};
            $conf    = $config_settings->{systemd_dropin_contents} || {};    # it may not be there... so, create it!
        }
        else {
            $section = $module_config->{$module}->{"section"};
            $setting = $module_config->{$module}->{"setting"};
            $conf    = $config_settings->{local_mycnf_contents};
        }

        if ( exists $module_config->{$module}->{'skip_if'}
            && $module_config->{$module}->{'skip_if'}($conf) ) {
            next;
        }

        my $max             = _normalize_number( $module_config->{$module}->{'max'} );
        my $min             = _normalize_number( $module_config->{$module}->{'min'} );
        my $current_setting = 0;

        try {
            if (  !exists $module_config->{$module}->{'set-noconfig-to-recommend'}
                || exists $conf->{$section}{$setting} ) {
                $current_setting = _normalize_number( $conf->{$section}->{$setting} || $min );
            }
        }
        catch {
            Cpanel::Debug::log_warn( "Failed to parse current value for MySQL setting “$setting” in section “$section”: " . Cpanel::Exception::get_string($_) );
        };

        my $value = _normalize_number( $config_settings->{module_input}->{$module}->{'min-value'} || $module_config->{$module}->{'recommend'}->() || $min );

        if ( $value > $max ) {
            $value = $max;
        }
        _note( $verbose, "$setting current value: " . ( $current_setting || 'undef' ) );

        # never decrease the limit, unless force is applied
        if ( !$opts->{force} && $current_setting && $current_setting >= $value ) {
            _note( $verbose, "$setting: not decreasing value to $value" );
            next;
        }

        _note( $verbose, "$setting update value: $value" );

        if ($debug) {
            _note( $verbose, "update required, but skipped [debug mode]" );
            next;
        }

        require Cpanel::MysqlUtils::MyCnf;

        # we always need to update the my.cnf since not all the auto setting modules here use systemd
        # and the ones that do require a systemd setting use both (MariaDB 10.1 & 10.2) or don't care that the my.cnf entry is there (MySQL 5.7)
        Cpanel::MysqlUtils::MyCnf::update_mycnf(
            user    => 'root',
            mycnf   => $Cpanel::ConfigFiles::MYSQL_CNF,
            section => $module_config->{$module}->{"section"},
            items   => [ { $module_config->{$module}->{"setting"} => $value } ]
        );

        # if we need to update systemd and our auto setting module requires a systemd setting, we should emit that too
        if ( length $config_settings->{systemd_dropin_file} && $module_config->{$module}->{'systemd_section'} ) {
            Cpanel::MysqlUtils::MyCnf::update_mycnf(
                user    => 'root',
                mycnf   => $config_settings->{systemd_dropin_file},
                section => $module_config->{$module}->{"systemd_section"},
                items   => [ { $module_config->{$module}->{"systemd_setting"} => $value } ],
                perms   => 0644,
            );
        }

        push @modified, $module;
    }

    return @modified;
}

sub _note {
    my ( $verbose, $message ) = @_;
    return unless $verbose;
    Cpanel::Debug::log_info($message);
    return;
}

sub _wanted {
    my ( $module, $force, $cpanel_conf, $verbose ) = @_;

    return 1 if $force;

    my $module_config = _get_module_config();

    my $tweak       = $module_config->{$module}->{'config_key'};
    my $auto_adjust = $cpanel_conf->{$tweak} // 1;

    return 1 if $auto_adjust;
    _note( $verbose, "$module disabled by tweak setting '$tweak'" );
    return 0;
}

# The mysql.service.d limits.conf file can cause issues if MariaDB is installed CPANEL-11264
sub _remove_mysql_systemd_limits_file_if_needed {
    my ($is_systemd) = @_;

    return unless $is_systemd;

    my $systemd_service_name = Cpanel::MysqlUtils::Compat::get_systemd_service_name();
    my $need_reload          = 0;

    # Remove unneeded MySQL limits file as it can cause MariaDB to have issues CPANEL-11264
    foreach my $service (qw/mysql mysqld/) {
        next if $systemd_service_name eq $service;

        try {
            $need_reload ||= Cpanel::Autodie::unlink_if_exists("$Cpanel::MysqlUtils::Systemd::SYSTEMD_DROPIN_PATH/$service.service.d/limits.conf");
        }
        catch {
            Cpanel::Debug::log_warn( "Error deleting '$Cpanel::MysqlUtils::Systemd::SYSTEMD_DROPIN_PATH/$service.service.d/limits.conf': " . Cpanel::Exception::get_string($_) );
        };
    }

    return ( $need_reload, 'drop-in systemd unit file' );
}

# MariaDB wants some of its information stored in a systemd drop-in configuration file.
# Since the format is similar enough to my.cnf, we can use the same tools to
# manipulate it.
# https://mariadb.com/kb/en/library/systemd/
# https://mariadb.com/kb/en/library/server-system-variables/
# https://dev.mysql.com/doc/refman/5.7/en/using-systemd.html
sub _find_mariadb_or_mysql_file {
    my ($is_systemd) = @_;

    return unless $is_systemd;
    return unless Cpanel::MysqlUtils::Compat::apply_limits_to_systemd_unit();

    # mysql (MySQL < 5.7 & MariaDB 10.0), mariadb (MariaDB 10.1+), or mysqld (MySQL 5.7)
    my $drop_in_path = Cpanel::MysqlUtils::Systemd::get_systemd_drop_in_dir();

    my @files;
    mkdir $drop_in_path if !-e $drop_in_path;

    @files = (
        "$drop_in_path/limits.conf",
        "$drop_in_path/migrated-from-my.cnf-settings.conf",
    );

    foreach my $path (@files) {
        if ( -e $path ) {
            return {
                path     => $path,
                contents => Cpanel::MysqlUtils::MyCnf::Full::etc_my_cnf($path) || undef,
            };
        }
    }

    return {
        path => $files[0],
    };
}

sub _restart_mysql_for_modules {
    my ( $is_systemd, $module_list ) = @_;

    system( 'systemctl', 'daemon-reload' ) if $is_systemd;

    #The "1" tells it NOT to background the restart.
    require Cpanel::Services::Restart;
    Cpanel::Services::Restart::restartservice( 'mysql', 1 ) or do {
        require Cpanel::Services::Log;
        my ( $log_exists, $log ) = Cpanel::Services::Log::fetch_service_startup_log('mysql');
        die Cpanel::Exception::create(
            'RestartFailed',
            'After [asis,MySQL] options [list_and_quoted,_1] were adjusted, the system failed to restart [asis,MySQL] because of an error: [_2]',
            [
                $module_list,
                $log
            ]
        );

    };
    return 1;
}

sub _normalize_number {
    my ($text_number) = @_;

    $text_number =~ s/\s//g;

    # MySQL only permits K,M,G
    # https://dev.mysql.com/doc/refman/5.1/en/program-variables.html
    if ( $text_number =~ m{^([0-9]+)K$} ) {
        return ( $1 * 1024 );
    }
    elsif ( $text_number =~ m{^([0-9]+)M$} ) {
        return ( $1 * 1024 * 1024 );
    }
    elsif ( $text_number =~ m{^([0-9]+)G$} ) {
        return ( $1 * 1024 * 1024 * 1024 );
    }
    elsif ( $text_number =~ m{^([0-9]+)$} ) {
        return $1;
    }
    else {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid numeric value that MySQL understands.', [$text_number] );
    }

}

1;
