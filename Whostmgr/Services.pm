package Whostmgr::Services;

# cpanel - Whostmgr/Services.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Binaries                     ();
use Cpanel::ProcessInfo                  ();
use Cpanel::Config::CpConfGuard          ();
use Cpanel::Config::LoadCpConf           ();
use Cpanel::FileUtils::TouchFile         ();
use Cpanel::SafeRun::Simple              ();
use Cpanel::ServerTasks                  ();
use Cpanel::Services::Enabled            ();
use Cpanel::OS                           ();
use Cpanel::Debug                        ();
use Whostmgr::Templates::Chrome::Rebuild ();

our %LEGACY_DISABLE_FILES = (
    'httpd'      => ['apache'],
    'ftpd'       => [ 'proftpd', 'pureftpd', 'pure-ftpd', 'ftpserver' ],
    'imap'       => [ 'cpimap',  'imapd' ],
    'postgresql' => ['postgres'],
    'named'      => [ 'bind', 'powerdns' ],
    'spamd'      => ['spam'],
);

my @ADDITIONAL_SERVICES_TO_RESTART;

sub reload_service {
    require Whostmgr::Services::Load;
    goto \&Whostmgr::Services::Load::reload_service;
}

sub _service_is_dovecot {
    my ($service) = @_;
    foreach my $is_dovecot (qw(imap pop lmtp dovecot)) {
        return 1 if ( $service eq $is_dovecot );
    }
    return 0;
}

sub _restart_services {
    my %services = @_;

    foreach my $service (@ADDITIONAL_SERVICES_TO_RESTART) {
        $services{$service} = 1;
    }

    undef @ADDITIONAL_SERVICES_TO_RESTART;

    return {} if !scalar keys %services;    #no services to restart

    foreach my $service ( keys %services ) {
        if ( _service_is_dovecot($service) ) {
            $services{'dovecot'} = delete $services{$service};
        }
    }

    if ( my $pid = fork ) {
        waitpid $pid, 0;
    }
    elsif ( defined $pid ) {
        foreach my $service ( sort keys %services ) {
            Cpanel::Debug::log_info("Whostmgr::Services::_restart_services: $service");
            if ( exists $INC{'Whostmgr/RestartSrv.pm'} && $INC{'Cpanel/Carp.pm'} && $Cpanel::Carp::OUTPUT_FORMAT ne 'xml' ) {
                Whostmgr::RestartSrv::restartsrv( $service, $service );
            }
            else {
                require Cpanel::Services::Restart;
                Cpanel::Services::Restart::restartservice( $service, 1 );
            }
        }
        exit;
    }
    else {
        die "Whostmgr::Services::_restart_services failed to fork(): $!";
    }

    return \%services;
}

sub _sync_crontab {
    try {
        require Cpanel::Config::Crontab;
        Cpanel::Config::Crontab::sync_root_crontab();
    }
    catch {
        warn "Failed to sync root crontab: $_";
    };

    return;
}

sub is_running {
    my $service = shift;
    my $is_running;

    $service = 'imap' if $service eq 'pop';

    my $services = _services_to_manage_for($service);
    $services = [$service] unless ref $services eq 'ARRAY';

    foreach my $s (@$services) {
        $is_running = _get_service_status_via_servicemanager($s);
        $is_running ||= _get_service_status_via_restartsrv_script($s);
        $is_running ||= _get_service_status_via_check_service( user => $ENV{REMOTE_USER}, service => $s ) if $ENV{REMOTE_USER};
        last if $is_running;
    }

    return $is_running;
}

sub _get_service_status_via_servicemanager {
    my ($service) = @_;

    require Cpanel::ServiceManager;
    require Cpanel::ServiceManager::Mapping;
    my $service_name_to_module_map = Cpanel::ServiceManager::Mapping::get_service_name_to_service_manager_module_map();
    my $module                     = $service_name_to_module_map->{$service} || $service;

    my $srvmng;
    {
        local $@;
        $srvmng = eval { Cpanel::ServiceManager->new( 'service' => $module ); };
        return undef if !$srvmng;
    }

    # ->status can fail for a varity of reasons
    # which we currently treat as 0 for backwards compat
    local $@;
    return eval { $srvmng->status(); } ? 1 : 0;
}

sub _get_service_status_via_restartsrv_script {
    my ($service) = @_;
    require Cpanel::RestartSrv::Script;
    my $restart_script = Cpanel::RestartSrv::Script::get_restart_script($service);
    return undef if !$restart_script;
    my @cmd = ( $restart_script, '--status' );
    my $out = Cpanel::SafeRun::Simple::saferunallerrors(@cmd);

    # some scripts are not symlinks ( should only use status code when all scripts are converted )
    if ( Cpanel::RestartSrv::Script::can_use_status_code_for_service($service) ) {
        return ( $? == 0 ) ? 1 : undef;
    }
    elsif ( $out !~ m/is not running/ && $out !~ m/\bservice is down\b/ ) {
        return 1;
    }
    return undef;

}

sub _get_service_status_via_check_service {
    my (%options) = @_;
    require Cpanel::Services;
    return Cpanel::Services::check_service(%options);
}

sub _enable_without_restart {
    my $service = shift;

    if ( -e '/etc/' . $service . 'disable' ) {
        unlink '/etc/' . $service . 'disable';
    }

    # Additional files to remove per service, "soon" to be deprecated
    if ( exists $LEGACY_DISABLE_FILES{$service} ) {
        foreach my $file ( @{ $LEGACY_DISABLE_FILES{$service} } ) {
            unlink '/etc/' . $file . 'disable';
        }
    }

    if ( $service eq 'mailman' ) {
        my $cpconf_guard = Cpanel::Config::CpConfGuard->new();
        if ( $cpconf_guard->{'data'}->{'skipmailman'} ) {
            $cpconf_guard->{'data'}->{'skipmailman'} = 0;
            $cpconf_guard->save();
        }
        else {
            $cpconf_guard->abort();
        }
    }

    my $restart_service;
    if ( !is_running($service) ) {
        if ( $service eq 'mailman' ) {
            Cpanel::SafeRun::Simple::saferun('/usr/local/cpanel/bin/mailman-tool');
        }
        elsif ( $service eq 'ipaliases' ) {

            #does not need to restart
            undef $restart_service;
        }
        elsif ( $service eq 'spamd' || $service eq 'exim' ) {
            $restart_service = 'exim';
        }
        else {
            $restart_service = $service;
        }
    }

    return $restart_service;
}

{
    # dummy helper that always return a defined value
    sub _get_cpconf_value {
        my $key    = shift;
        my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
        return $cpconf->{$key} || '';
    }

    my $exceptions = {

        # only enable/disable the current server
        'ftpd' => sub {
            my $ftpserver = _get_cpconf_value('ftpserver');
            return ['proftpd']   if $ftpserver eq 'proftpd';
            return ['pure-ftpd'] if $ftpserver eq 'pure-ftpd';
            return;
        },
        'named' => sub {
            my $nameserver = _get_cpconf_value('local_nameserver_type');
            return ['pdns'] if $nameserver eq 'powerdns';
            return ['named'];    # if $nameserver eq 'named', and use as fallback now
        },

        # no service like this one, simply skip it
        'exim-altport' => undef,

        # imap & pop are controlled by mail ( they are linked together )
        'imap' => undef,
        'pop'  => undef,
        'mail' => sub {
            return ['dovecot'];
        },
        'mysql' => sub {
            require Cpanel::Database;
            return Cpanel::Database->new()->possible_service_names;
        },
    };

    sub _services_to_manage_for {
        my $s = shift;
        return unless defined $s;
        if ( exists $exceptions->{$s} ) {
            if ( ref $exceptions->{$s} eq 'CODE' ) {
                return $exceptions->{$s}->();
            }
            return $exceptions->{$s};
        }

        # by default return the current service name
        #  it's a non issue if we try to enable/disable an unknown service
        return [$s];
    }
}

# Enable services and enable monitoring on those service(s) which were not already enabled.
# This preserves an enabled service's existing monitoring setting, but provides a "monitor by default" behavior.
sub enable_and_monitor {
    my %skip_monitor = map { $_ => Cpanel::Services::Enabled::is_enabled($_) } @_;
    return _do_enable_and_monitor( \@_, \%skip_monitor );
}

# Always try to enable monitoring on service(s)
sub enable_and_force_monitor {
    return _do_enable_and_monitor( \@_, {} );
}

sub _do_enable_and_monitor {
    my ( $services_ar, $skip_monitor_hr ) = @_;

    require Cpanel::Chkservd::Manage;
    require Cpanel::Chkservd::Tiny;

    my @enable_result = enable(@$services_ar);
    my @not_enabled   = @{ $enable_result[3] };

    # Only try to enable monitoring on service(s) successfully enabled.
    for my $not_enabled_service (@not_enabled) {
        $skip_monitor_hr->{$not_enabled_service} = 1;
    }

    my %can_monitor = map { $_ => 1 } keys %{ Cpanel::Chkservd::Manage::load_drivers() };

    for my $service (@$services_ar) {
        if ( $can_monitor{$service} && !$skip_monitor_hr->{$service} ) {
            Cpanel::Debug::log_info("Whostmgr::Services enable monitoring: $service");
            Cpanel::Chkservd::Tiny::suspend_service($service);    # Give time for the service to be ready before first status check.
            Cpanel::Chkservd::Manage::enable($service);
        }
    }

    return @enable_result;
}

sub _preverify_services_to_enable (@services) {
    for my $service (@services) {
        if ( $service eq 'cpdavd' ) {
            require Cpanel::ServiceConfig::cpdavd;

            # Nothing that wants to enable cpdavd should ever get here.
            # If it does, that’s worth throwing on.
            Cpanel::ServiceConfig::cpdavd::die_if_unneeded();
        }
    }

    return;
}

sub enable {
    my @services = @_;
    my %restart_services;
    my @not_enabled;

    my $have_apache_takeover_www_and_ssl_ports = 0;

    _preverify_services_to_enable(@services);

    foreach my $service (@services) {

        my $service_is_httpd = ( $service eq 'httpd' ) || grep { $_ eq $service } @{ $LEGACY_DISABLE_FILES{'httpd'} };

        # Filter out exim-altport since it's a “psuedo service” configured via Service Manager and Whostmgr::API::1::Services
        # It can now be disallowed by disabling the Cpanel::Server::Type::Role::MailSend server role, and this makes sure we don't
        # accidentally try to do a restartsrv on it.
        next if $service eq 'exim-altport';

        my $restart_service = _enable_without_restart($service);
        if ( defined $restart_service ) {
            $restart_services{$restart_service} = 1;
        }

        # make sure the service status will be preserved after a reboot
        Cpanel::Services::Enabled::remove_disable_files($service);

        if ( $service eq 'nscd' ) {
            _toggle_bootability_for_service( 'nscd', 1 );
        }
        elsif ( $service eq 'cpgreylistd' ) {
            require Cpanel::GreyList::Config;
            Cpanel::GreyList::Config::enable();
            next;
        }
        elsif ( $service eq 'cphulkd' ) {
            require Cpanel::Config::Hulk;
            Cpanel::Config::Hulk::enable();
            if ( $restart_services{$service} ) {
                require Cpanel::SafeRun::Object;

                # TODO: taskqueue this
                _rebuild_dovecot_conf();

                # dovecot needs to restart first so the service is available to talk to cpsrvd
                _schedule_dovecot_restart();
                Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 10, 'restartsrv cpsrvd' );
            }
            next;
        }
        elsif ( $service eq 'cpanel-dovecot-solr' ) {
            _rebuild_dovecot_conf();
            _schedule_dovecot_restart();
        }
        elsif ( $service eq 'cpanel_php_fpm' && $restart_services{$service} ) {
            require Cpanel::Server::FPM::Manager;
            local $@;
            eval { Cpanel::Server::FPM::Manager::sync_config_files(); } or warn $@;
        }
        elsif ( $service eq 'mailman' ) {

            # We must restart apache so that the mailman URLs will begin to work
            Cpanel::ServerTasks::schedule_task( ['ApacheTasks'], 10, 'apache_restart' );
        }

        if ($service_is_httpd) {

            # Now that we’ve indicated that httpd is to be enabled,
            # we need to restart cpsrvd so it will abandon the
            # ports that httpd opens.
            $have_apache_takeover_www_and_ssl_ports = 1;
        }

        # enable the service at systemd/systemv level
        _do_cpservice( _services_to_manage_for($service), 'enable' );

        if ( Cpanel::Services::Enabled::is_enabled($service) ) {
            if ( $service eq 'mysql' ) {

                Cpanel::ServerTasks::schedule_task( ['MysqlTasks'], 60, 'sync_db_grants_from_disk' );
            }
            elsif ($service_is_httpd) {

                # httpd being enabled/disabled may require a reconfiguration of
                # Mailman’s permissions.
                _fix_mailman();
            }
        }
        elsif ( !grep { index( $service, $_ ) != -1 } qw{imap pop} ) {

            # Don't try pushing this to the 'not_enabled' services
            # if it is pop or IMAP, as we do that below.
            push @not_enabled, $service;
        }
    }

    # special case when enabling: imap or pop
    if ( grep { m{^(imap|pop)$} } @services ) {
        my %services_to_enable = map { $_ => 1 } @services;
        require Cpanel::Dovecot::Service;
        Cpanel::Dovecot::Service::set_dovecot_service_state(
            'protocols' => {
                'pop3' => $services_to_enable{'pop'}  ? 1 : Cpanel::Services::Enabled::is_enabled('pop'),
                'imap' => $services_to_enable{'imap'} ? 1 : Cpanel::Services::Enabled::is_enabled('imap'),
            }
        );

        # we know that we are enabling one of the mail service
        _do_cpservice( _services_to_manage_for('mail'), 'enable' );

        # We should at least restart it so that the config is updated.
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv dovecot" );
    }

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 5, 'build_global_cache' );

    if ($have_apache_takeover_www_and_ssl_ports) {
        delete $restart_services{'httpd'};

        # Have cpsrvd give them up
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 15, 'restartsrv cpsrvd' );

        # And have apache take them over.  We wait 60 seconds to ensure
        # cpsrvd has enough time to restart.  Ideally we would be able to make
        # these dependant, however we don't have that option so we schedule it out
        # a bit more than we really expect we need to do.
        Cpanel::ServerTasks::schedule_task( ['ApacheTasks'], 60, 'apache_restart --force' );
    }

    Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();

    my @result = scalar @not_enabled ? ( 0, "@not_enabled not enabled successfully" ) : ( 1, 'Services Enabled' );

    _trigger_dynamicui_updates();

    _sync_crontab();

    return ( @result, _restart_services(%restart_services), \@not_enabled );
}

sub _toggle_bootability_for_service {
    my ( $service, $state ) = @_;

    my $is_systemd     = Cpanel::OS::is_systemd();
    my $program        = $is_systemd ? 'systemctl'   : 'chkconfig';
    my $sv_up_status   = $is_systemd ? 'enable'      : 'on';
    my $sv_down_status = $is_systemd ? 'disable'     : 'off';
    my $sv_state       = $state      ? $sv_up_status : $sv_down_status;
    my @args           = ( $service, $sv_state );

    # TODO: this duplicates Cpanel::Init::Simple functionality
    @args = reverse @args if $is_systemd;
    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new(
        program      => $program,
        timeout      => 86400,
        read_timeout => 86400,
        args         => \@args,
    );
    my $error = $run->stderr() || '';
    Cpanel::Debug::log_warn("Error while trying to enable $service starting on boot: $error") if $run->CHILD_ERROR();
    return 1;
}

sub _fix_mailman {
    require Cpanel::SafeRun::Object;
    my $run = Cpanel::SafeRun::Object->new(
        program => '/usr/local/cpanel/scripts/fixmailman',
        stdout  => \*STDERR,
        stderr  => \*STDERR,
    );

    warn $run->autopsy() if $run->CHILD_ERROR();

    return;
}

sub stop {
    my $service = shift;
    require Cpanel::RestartSrv::Script;
    my $restart_script = Cpanel::RestartSrv::Script::get_restart_script($service);
    if ( defined $restart_script ) {
        my @cmd    = ( $restart_script, '--stop', '--html' );
        my $output = Cpanel::SafeRun::Simple::saferun(@cmd);
        print $output if $INC{'Cpanel/Carp.pm'} && $Cpanel::Carp::OUTPUT_FORMAT eq 'html';
        return 1;
    }
    else {
        my @lineage = Cpanel::ProcessInfo::get_pid_lineage();

        if ( $service eq 'ftpd' ) {
            require Cpanel::Kill;
            Cpanel::Kill::safekill( [ 'proftpd', 'pure-ftpd' ], undef, undef, \@lineage );
        }
        else {
            require Cpanel::SafeRun::Object;
            my $run = Cpanel::SafeRun::Object->new(
                'program'      => Cpanel::Binaries::path('service'),
                'args'         => [ $service, 'stop' ],
                'timeout'      => 120,
                'read_timeout' => 120,
            );

            if ( $run->CHILD_ERROR() ) {
                Cpanel::Debug::log_warn( $run->autopsy() );
            }
            require Cpanel::Kill;
            Cpanel::Kill::safekill( $service, undef, undef, \@lineage );
        }

        return 1;
    }

    return;
}

sub _do_cpservice {
    my ( $services, $action ) = @_;
    return unless defined $services && defined $action && ref $services eq 'ARRAY';

    require Cpanel::Init::Simple;
    foreach my $s (@$services) {
        Cpanel::Init::Simple::call_cpservice_with( $s, $action );
    }

    return;
}

sub disable {
    my @services = @_;
    my $result   = 1;
    my @msgs;
    my $do_cpsrvd_restart = 0;

    require Cpanel::Chkservd::Manage;
    require Cpanel::Services::List;

    my $service_list = Cpanel::Services::List::get_service_list();

    foreach my $service (@services) {

        # Filter out exim-altport since it's a “psuedo service” configured via Service Manager and Whostmgr::API::1::Services
        # It can now be disallowed by disabling the Cpanel::Server::Type::Role::MailSend server role, and this makes sure we don't
        # accidentally try to do a restartsrv on it.
        if ( $service eq 'exim-altport' ) {

            require Whostmgr::Services::exim_altport;
            my $current_exim_altport = Whostmgr::Services::exim_altport::get_current_exim_altport();

            if ( $current_exim_altport && !Cpanel::Chkservd::Manage::disable("exim-$current_exim_altport") ) {
                push @msgs, "Unable to disable chkservd monitoring for $service.";
            }

            next;
        }

        if ( $service eq 'nscd' ) {
            _toggle_bootability_for_service( 'nscd', 0 );
        }

        if ( $service_list->{$service}{'always_enabled'} ) {
            push @msgs, "You cannot disable the service “$service”.";
            undef $result;
            next;
        }

        my $service_is_dovecot = _service_is_dovecot($service);

        if ( !$service_is_dovecot && is_running($service) ) {
            stop($service);
        }

        # make sure the service status will be preserved after a reboot
        if ( !Cpanel::Services::Enabled::touch_disable_file($service) ) {
            undef $result;
            push @msgs, "Unable to touch disable file for $service.";
        }

        # also disable the service at systemd/systemv level
        unless ($service_is_dovecot) {
            local $@;
            eval {
                local $SIG{'__WARN__'} = sub { };
                _do_cpservice( _services_to_manage_for($service), 'disable' );
            };

            # This may fail since not all services have cpservice files, however
            # we must call disable since there may be init scripts installed for
            # legacy services and/or older servers.
        }

        if ( !Cpanel::Chkservd::Manage::disable($service) ) {
            push @msgs, "Unable to disable chkservd monitoring for $service.";
        }

        if ( $service eq 'mailman' ) {
            my $cpconf_guard = Cpanel::Config::CpConfGuard->new();
            if ( !$cpconf_guard->{'data'}->{'skipmailman'} ) {
                $cpconf_guard->{'data'}->{'skipmailman'} = 1;
                $cpconf_guard->save();
            }
            else {
                $cpconf_guard->abort();
            }

            # We used to stop Mailman here by calling $ULC/bin/mailman-tool,
            # but since we’ve just stop()ped the service there’s no need.

            # We must restart apache so that the mailman URLs will stop working
            Cpanel::ServerTasks::schedule_task( ['ApacheTasks'], 10, 'apache_restart' );
        }
        elsif ( $service eq 'cphulkd' ) {
            require Cpanel::Config::Hulk;
            Cpanel::Config::Hulk::disable();
            require Cpanel::SafeRun::Object;

            # TODO : taskqueue this
            Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/local/cpanel/scripts/builddovecotconf' );
            $do_cpsrvd_restart = 1;
            Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 10, "restartsrv dovecot" );
        }
        elsif ( $service eq 'cpanel-dovecot-solr' ) {
            _rebuild_dovecot_conf();
        }
        elsif ( $service eq 'p0f' ) {
            require Whostmgr::TweakSettings;
            Whostmgr::TweakSettings::set_value( 'Mail', 'spamassassin_plugin_P0f', 0 );
        }

        # Create additional disable files for legacy compatibility with
        # old restartsrv scripts
        if ( exists $LEGACY_DISABLE_FILES{$service} ) {
            foreach my $file ( @{ $LEGACY_DISABLE_FILES{$service} } ) {
                if ( !Cpanel::FileUtils::TouchFile::touchfile( '/etc/' . $file . 'disable' ) ) {
                    undef $result;
                    push @msgs, "Unable to touch disable file for $file.";
                }
            }
        }
    }

    my %services_to_disable = map { $_ => 1 } @services;

    # special case when disabling: imap or pop if imap & pop are disabled
    if ( grep { _service_is_dovecot($_) } @services ) {

        # one of the service might be already be disable need to be sure that both are disabled
        if (   !Cpanel::Services::Enabled::is_enabled('imap')
            && !Cpanel::Services::Enabled::is_enabled('pop') ) {
            _do_cpservice( _services_to_manage_for('mail'), 'disable' );
        }

        require Cpanel::Dovecot::Service;
        Cpanel::Dovecot::Service::set_dovecot_service_state(
            'protocols' => {
                'pop3' => $services_to_disable{'pop'}  ? 0 : Cpanel::Services::Enabled::is_enabled('pop'),
                'imap' => $services_to_disable{'imap'} ? 0 : Cpanel::Services::Enabled::is_enabled('imap'),
            }
        );

        # We should at least restart it so that the config is updated.
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, "restartsrv dovecot" );

    }

    my $restarted_httpd = grep { $services_to_disable{$_} } 'httpd', @{ $LEGACY_DISABLE_FILES{'httpd'} };

    if ($restarted_httpd) {

        # httpd being enabled/disabled may require a reconfiguration of
        # Mailman’s permissions.
        _fix_mailman();

        # Now that we’ve disabled Apache, we should schedule a cpsrvd restart
        # to have cpsrvd claim the standard HTTP ports.
        $do_cpsrvd_restart = 1;
    }

    # We can schedule this in the backgroun since http has already been stopped
    Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 5, 'restartsrv cpsrvd' ) if $do_cpsrvd_restart;

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 5, 'build_global_cache' );

    Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();

    _trigger_dynamicui_updates();

    _sync_crontab();

    return $result, join( "\n", @msgs );
}

sub add_services_to_restart {
    my @services = @_;
    push @ADDITIONAL_SERVICES_TO_RESTART, @services;
    return;
}

sub _trigger_dynamicui_updates {

    require Cpanel::ConfigFiles;

    my $now = time();
    utime( $now, $now, $Cpanel::ConfigFiles::cpanel_config_file ) or do {
        warn "utime($Cpanel::ConfigFiles::cpanel_config_file): $!";
    };

    return;
}

sub _rebuild_dovecot_conf {
    Cpanel::SafeRun::Object->new_or_die( 'program' => '/usr/local/cpanel/scripts/builddovecotconf' );
    return;
}

sub _schedule_dovecot_restart {
    Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 5, "restartsrv dovecot" );
    return;
}

1;

__END__
