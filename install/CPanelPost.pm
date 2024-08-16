package Install::CPanelPost;

# cpanel - install/CPanelPost.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use base qw( Cpanel::Task );

use Cwd                          ();
use FileHandle                   ();
use File::Find                   ();
use Cpanel::Autodie              qw(unlink);
use Cpanel::TimeHiRes            ();
use Cpanel::Config::LoadCpConf   ();
use Cpanel::ConfigFiles          ();
use Cpanel::Debug                ();
use Cpanel::Features::Write      ();
use Cpanel::Features::Load       ();
use Cpanel::Features::Lists      ();
use Cpanel::FileUtils::Copy      ();
use Cpanel::FileUtils::Lines     ();
use Cpanel::FileUtils::TouchFile ();
use Cpanel::FileUtils::Write     ();
use Cpanel::LoginProfile         ();
use Cpanel::JailSafe::Install    ();
use Cpanel::LoadFile             ();
use Cpanel::OS                   ();
use Cpanel::Pkgr                 ();
use Cpanel::SafeRun::Simple      ();
use Cpanel::ServerTasks          ();
use Cpanel::Services::Enabled    ();

our $VERSION = '1.5';

=head1 DESCRIPTION

    This task is mainly a placeholder for actions to perform
    after an update/install...

    Most of these actions are only run onced, and are using a 'version' flag file
    to only be triggered once during an upgrade.

=over 1

=item Type: Fresh Install, Sanity

=item Frequency: always

=item EOL: never

=back

=cut

exit __PACKAGE__->runtask() unless caller;

sub log_warn ( $msg = undef ) {

    $msg //= $@;

    if ( ref $msg && $msg->isa("Cpanel::Exception") ) {
        $msg = $msg->to_string;
    }

    return unless length($msg);

    return Cpanel::Debug::log_warn_no_backtrace($msg);
}

sub log_info ( $msg = undef ) {
    return unless length $msg;

    return Cpanel::Debug::log_info($msg);
}

sub new ($proto) {
    my $self = $proto->SUPER::new;

    $self->set_internal_name('cpanelpost');
    $self->add_dependencies(qw( post taskqueue susetup ));

    $self->{'-dns-version-file'} = '/var/cpanel/version/dnsversion';

    return $self;
}

sub _check_version_file_and_default_feature ( $version_file, $feature_key, $feature_value ) {    ## no critic qw(ProhibitManyArgs)

    my $version_file_path = "/var/cpanel/version/$version_file";

    if ( !-e $version_file_path ) {
        if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $version_file_path, time, 0644 ) ) {
            log_warn('Unable to write version file');
            return;
        }

        _add_default_feature_entry( $feature_key => $feature_value );
    }
    return 1;
}

sub _add_default_feature_entry ( $key, $value ) {

    if ( !eval { Cpanel::Features::Lists::ensure_featurelist_dir(); return 1; } ) {
        log_warn("Unable to create feature directory '$Cpanel::ConfigFiles::FEATURES_DIR': $@");
        return;
    }

    Cpanel::FileUtils::TouchFile::touchfile('/var/cpanel/features/default') if !-e '/var/cpanel/features/default';

    my $features = eval { Cpanel::Features::Load::load_featurelist('default') };
    if ( !$@ && $features ) {
        $features->{$key} = $value;
        Cpanel::Features::Write::write_featurelist( 'default', $features );
    }
    else {
        log_warn("Unable to add default feature entry $key=$value: $@");
    }
    return 1;
}

sub _disable_api_shell_by_default() {
    return _check_version_file_and_default_feature(
        'api_shell',
        'api_shell' => 0,
    );
}

sub _disable_adv_zone_edit_by_default() {
    return _check_version_file_and_default_feature(
        'advanced_zone_editor_install',
        'zoneedit' => 0,
    );
}

sub _disable_modsec_by_default() {
    return _check_version_file_and_default_feature(
        'modsecurity',
        'modsecurity' => 0,
    );
}

sub _disable_manage_team_by_default() {
    return _check_version_file_and_default_feature(
        'team_manager',
        'team_manager' => 0,
    );
}

sub _write_version_file() {
    my $version_file = '/var/cpanel/version/6.2';
    if (   !-e $version_file
        && !Cpanel::FileUtils::Write::overwrite_no_exceptions( $version_file, time, 0644 ) ) {
        log_warn('Unable to write version file');
        return;
    }
    return 1;
}

sub _repair_bind_views ( $self, @options ) {

    my $dns_version_file = $self->{'-dns-version-file'};

    _run( '/usr/local/cpanel/scripts/fixnamedviews', @options );
    if ( !Cpanel::FileUtils::Lines::appendline( $dns_version_file, 'dns 11.17:' . time ) ) {
        log_warn('Unable to write dns version file');
        return;
    }

    return 1;
}

sub _repair_bind_rndc_config ($self) {

    my $dns_version_file = $self->{'-dns-version-file'};

    _run( '/usr/local/cpanel/scripts/fixrndc', '-f' );
    if ( !Cpanel::FileUtils::Lines::appendline( $dns_version_file, 'dns 10.5:' . time ) ) {
        log_warn('Unable to write dns version file');
        return;
    }

    return 1;
}

sub _configure_bind ($self) {

    if ( Cpanel::Services::Enabled::is_enabled('named') ) {
        my $dns_version_file = $self->{'-dns-version-file'};
        if ( !-e $dns_version_file ) {
            $self->_repair_bind_views('--norestart');
            $self->_repair_bind_rndc_config();
        }
        else {
            if ( !Cpanel::FileUtils::Lines::has_txt_in_file( $dns_version_file, 'dns 11.17:' ) ) {
                $self->_repair_bind_views();
            }

            if ( !Cpanel::FileUtils::Lines::has_txt_in_file( $dns_version_file, 'dns 10.5:' ) ) {
                $self->_repair_bind_rndc_config();
            }
        }
    }

    _run('/usr/local/cpanel/scripts/fix-listen-on-localhost');

    if ( !-e '/var/cpanel/skip_nsd_badzones_notification' ) {
        my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
        if ( ( $cpconf_ref->{'local_nameserver_type'} || '' ) eq 'nsd' ) {
            _run('/usr/local/cpanel/bin/check_nsd_badzones');
        }
    }
    return;
}

sub _symlink_jail_safe_crontab {
    return Cpanel::JailSafe::Install::do_symlink_jail_safe_for( 'crontab', 1 );
}

sub _symlink_jail_safe_passwd {
    return Cpanel::JailSafe::Install::do_symlink_jail_safe_for('passwd');
}

# could be provided by the base task
sub _run (@cmd) {

    return unless defined $cmd[0] && length( $cmd[0] );

    # get command name
    my ( $bin, $trash ) = split( ' ', $cmd[0], 2 );
    my $name = ( split( '/', $bin ) )[-1];

    _msg_start($name);

    # also redirect STDERR to STDOUT
    my $start_time = Cpanel::TimeHiRes::time();
    my $output     = Cpanel::SafeRun::Simple::_saferun_r( \@cmd, 1 );
    my $end_time   = Cpanel::TimeHiRes::time();
    my $exec_time  = sprintf( "%.3f", ( $end_time - $start_time ) );
    map { _msg($_) } split( "\n", $$output );
    _msg_stop( $name, "in $exec_time second(s)." );

    # needed for the cp7 call
    return $$output;
}

# If fork bomb protection is enabled, disable and re-enable to ensure the updated limits are applied, if any.
sub _update_fork_bomb_limits() {

    if ( Cpanel::LoginProfile::profile_is_installed('limits') ) {
        Cpanel::LoginProfile::remove_profile('limits');
        if ( !Cpanel::OS::is_cloudlinux() ) {
            Cpanel::LoginProfile::install_profile('limits');
        }
    }

    return;
}

sub _update_php_wrappers() {
    my $wrapper_version_file = '/var/cpanel/version/php-wrappers-2';
    if ( !-e $wrapper_version_file ) {
        if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $wrapper_version_file, time, 0644 ) ) {
            log_warn('Failed to write php-wrappers file');
        }
        my $cgisys = '/usr/local/cpanel/cgi-sys';
        if ( opendir( my $dh, $cgisys ) ) {
            while ( my $filename = readdir($dh) ) {
                next unless $filename =~ /^(?:ea-)php\d+$/;

                # Skip if using a custom wrapper
                next if -e "/var/cpanel/conf/apache/wrappers/$filename";

                # Skip if the permissions or ownership are different from cPanel defaults
                my $dest_wrapper = "/usr/local/cpanel/cgi-sys/$filename";
                my ( $perm, $uid, $gid ) = ( stat($dest_wrapper) )[ 2, 4, 5 ];
                next unless ( defined $perm && $uid == 0 && $gid == 10 && ( 0755 == ( $perm & 07777 ) ) );

                # Replace with new wrapper
                next unless unlink $dest_wrapper;
                Cpanel::FileUtils::Copy::safecopy( "/usr/local/cpanel/bin/php-wrapper", $dest_wrapper );
                chown 0, 10, $dest_wrapper;
                chmod 0755, $dest_wrapper;
            }
            closedir $dh;
        }
    }
    return 1;
}

# some aliases
sub _msg_start {
    return _msg_bold( 'Running', @_ );
}

sub _msg_stop {
    return _msg_bold( 'Done', @_ );
}

sub _msg_bold {
    return _msg( '***', @_, '***' );
}

sub _msg {
    return log_info( join( ' ', @_ ) );
}

sub perform ($self) {

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    if ( !-e '/var/cpanel/server_locale' ) {
        local $@;

        # eval wrapped just in case it gets created by another caller between -e
        # and write
        eval { Cpanel::FileUtils::Write::write( '/var/cpanel/server_locale', $cpconf->{'server_locale'}, 0644 ); };
        log_warn();
    }

    if ( !-e '/var/cpanel/maxemailsperhour' ) {
        _run('/usr/local/cpanel/scripts/build_maxemails_config');
    }

    if ( !-e "/usr/local/cpanel/.cpanel" ) {
        mkdir( '/usr/local/cpanel/.cpanel', 0755 );
        require Cpanel::FileUtils::Access;
        Cpanel::FileUtils::Access::ensure_mode_and_owner( '/usr/local/cpanel/.cpanel', 0755, 'cpanel' );
    }

    _run_modulino_script(
        '/usr/local/cpanel/bin/legacy_cfg_installer',
        'bin::legacy_cfg_installer'
    );

    _run("/usr/local/cpanel/bin/register_hooks");

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {
        _run_modulino_script(
            '/usr/local/cpanel/bin/build_userdata_cache',
            'bin::build_userdata_cache'
        );
    }

    _run_modulino_script(
        '/usr/local/cpanel/bin/migrate_tweak_settings',
        'bin::migrate_tweak_settings'
    );

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {
        local $@;
        eval { Cpanel::ServerTasks::queue_task( ['cPAddons'], 'install_cpaddons' ) };
        log_warn();
    }

    _write_version_file();
    _disable_adv_zone_edit_by_default();
    _disable_api_shell_by_default();
    _disable_modsec_by_default();
    _disable_manage_team_by_default();
    $self->_configure_bind();
    _symlink_jail_safe_crontab();
    _symlink_jail_safe_passwd();
    _update_php_wrappers();
    _update_fork_bomb_limits();

    foreach my $api (qw(cpapi1 cpapi2 cpapi3 uapi)) {
        if ( !-e "/usr/bin/$api" ) {
            symlink( "../../usr/local/cpanel/bin/$api", "/usr/bin/$api" );
        }
    }

    foreach my $api (qw(whmlogin)) {
        if ( !-e "/usr/sbin/$api" ) {
            symlink( "../../usr/local/cpanel/scripts/$api", "/usr/sbin/$api" );
        }
    }

    foreach my $api (qw(whmapi0 whmapi1)) {
        if ( !-e "/usr/sbin/$api" ) {
            symlink( "../../usr/local/cpanel/bin/$api", "/usr/sbin/$api" );
        }
    }

    my $req_version = Cpanel::LoadFile::loadfile('/usr/local/cpanel/etc/required_exim_acl_version');
    $req_version =~ s/\n//g;
    $req_version ||= '9.0';

    {
        # Don’t ever put this after check_exim_config or a buildeximconf because Exim config
        # could be updated in some incompatible way before the cache is initialized.

        require '/usr/local/cpanel/scripts/refresh-dkim-validity-cache';    ## no critic(RequireBarewordIncludes)
        local $@;
        eval { scripts::refresh_dkim_validity_cache->new('--initialize')->run(); };
        log_warn();

        # Needed to ensure that the access control is as intended.
        require Cpanel::DKIM::ValidityCache::Write;
        eval { Cpanel::DKIM::ValidityCache::Write->initialize(); };
        log_warn();
    }

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {
        _run( '/usr/local/cpanel/bin/check_exim_config', '--newest_allowed_version=dist', '--must_have_at_least_acl_version=' . $req_version );
    }

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {
        local $@;
        eval { Cpanel::ServerTasks::schedule_task( ['API'], 1, "verify_api_spec_files" ); };
        log_warn();
    }

    if (  !-e '/var/cpanel/version/securetmp_disabled'
        && -e '/etc/rc.local'
        && Cpanel::FileUtils::Lines::has_txt_in_file( '/etc/rc.local', 'securetmp' ) ) {
        _run( '/usr/local/cpanel/scripts/securetmp', '--install' );
    }

    if ( -e '/usr/tmpDSK' ) {
        chmod 0600, '/usr/tmpDSK';
    }

    _run_modulino_script(
        '/usr/local/cpanel/scripts/setpostgresconfig',
        'scripts::setpostgresconfig' => 'run',
    );

    if ( !$ENV{'CPANEL_BASE_INSTALL'} ) {
        local $@;
        eval { Cpanel::ServerTasks::schedule_task( ['TemplateTasks'], 1, "rebuild_templates" ); };
        log_warn();
    }

    #NOTE: By this time we expect any new services that have been added
    #in this build that are not on by default have been disabled (ie cpanel_php_fpm)
    #

    {
        require '/usr/local/cpanel/scripts/check_unmonitored_enabled_services';    ##no critic qw(RequireBarewordIncludes)
        local $@;
        eval { scripts::check_unmonitored_enabled_services->script( ['--notify'] ); };
        log_warn();
    }

    # This is here to ensure that, if anything prior to here
    # removed domains from /etc/userdomains, we’ll replace them:
    print "\n";
    _run( '/usr/local/cpanel/scripts/updateuserdomains', '--force' );

    return 1;
}

sub _run_modulino_script ( $file, $namespace, $subname = 'script' ) {

    log_info("Running modulino ${namespace}::${subname}");

    local $@;
    eval {
        require $file;
        my $run = $namespace->can($subname) or die qq[Missing script from $namespace];
        $run->();
        1;
    } or log_warn("Error from modulino $namespace: $@");

    return;
}

1;

__END__
