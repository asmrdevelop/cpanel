package Cpanel::AppConfig::Register;

# cpanel - Cpanel/AppConfig/Register.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Signal                       ();
use Cpanel::AppConfig                    ();
use Cpanel::Debug                        ();
use Cpanel::FileUtils::Write             ();
use Cpanel::AdminBin::Serializer         ();
use Cpanel::TempFile                     ();
use Cpanel::Locale                       ();
use Cpanel::Notify                       ();
use Cpanel::IP::Remote                   ();
use Cpanel::LoadFile                     ();
use Cpanel::ServerTasks                  ();
use Whostmgr::Plugins                    ();
use Whostmgr::Templates::Chrome::Rebuild ();

my $empty_appconfig = {
    'whostmgr' => [],
    'cpanel'   => [],
    'webmail'  => [],
};

sub new {
    my ($class) = @_;

    my $self = bless {}, $class;

    $self->_ensure_dirs();

    return $self;

}

sub register {
    my ( $self, $config, $original_config_file_path ) = @_;

    my ( $appconfig_status, $appconfig_statusmsg, $appref ) = _process_appconfig( $config, $original_config_file_path );

    return ( $appconfig_status, $appconfig_statusmsg ) if !$appconfig_status;

    my $service = _find_service_with_appconfig($appref);

    if ( !$appref->{$service} || !$appref->{$service}->[0] ) {
        return ( 0, "Failed to parse appconfig" );
    }

    my $app = $appref->{$service}->[0]->{'name'};

    if ( !length $app ) {
        return ( 0, "name is missing from appconfig data." );
    }

    my $already_registered = 0;
    my $applist            = Cpanel::AppConfig::get_application_list();

    if ( exists $applist->{$service} ) {
        if ( grep { $_->{'name'} eq $app } @{ $applist->{$service} } ) {
            $already_registered = 1;
        }
    }

    my $url = $appref->{$service}->[0]->{'url'};

    if ( !length $url ) {
        return ( 0, "url is missing from appconfig data. You must provide at least one url." );
    }

    my ( $conf_path_status, $conf_path ) = $self->_get_conf_path($app);
    return ( $conf_path_status, $conf_path ) if !$conf_path_status;

    if ( !$appconfig_status ) {
        return ( $appconfig_status, $appconfig_statusmsg );
    }

    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $conf_path, $config, 0600 ) ) {
        return ( 0, "Failed to write $conf_path: $!" );
    }

    $self->_verify_api_spec();
    $self->_reset_whostmgr_plugin_cache() if $service eq 'whostmgr';
    $self->_reload_cpsrvd();

    if ( !$already_registered ) {
        Cpanel::Notify::notification_class(
            application      => 'appconfig',
            interval         => 1,
            status           => 'registered',
            class            => 'appconfig::Notify',
            constructor_args => [
                origin              => 'appconfig',
                'source_ip_address' => Cpanel::IP::Remote::get_current_remote_ip(),
                %{ $appref->{$service}->[0] },
                service => $service,
            ],
        );
    }

    return ( 1, "$app registered" );
}

sub unregister {
    my ( $self, $config, $original_config_file_path ) = @_;

    my ($app) = $config =~ m/^name=[\t ]*([a-zA-Z0-9_-]+)/m;

    if ( !length $app ) {
        return ( 0, "name is missing from appconfig data." );
    }

    my ( $conf_path_status, $conf_path ) = $self->_get_conf_path($app);

    return ( $conf_path_status, $conf_path ) if !$conf_path_status;

    my ( $appconfig_status, $appconfig_statusmsg, $appref ) = _process_appconfig( scalar Cpanel::LoadFile::loadfile($conf_path), $original_config_file_path );
    my $service = _find_service_with_appconfig($appref);

    if ( !-f $conf_path && -f lc($conf_path) ) {
        $conf_path = lc($conf_path);
    }

    my $status_msg;
    if ( unlink $conf_path ) {
        $status_msg = "$app unregistered";
    }
    else {
        $status_msg = "Failed to remove file: $conf_path : $!";
    }

    $self->_verify_api_spec();
    $self->_reset_whostmgr_plugin_cache() if ( $service && $service eq 'whostmgr' );
    $self->_reload_cpsrvd();

    return ( 1, $status_msg );
}

sub _verify_api_spec {

    local $@;
    eval { Cpanel::ServerTasks::schedule_task( ['API'], 1, "verify_api_spec_files" ); };
    if ($@) {
        Cpanel::Debug::log_warn( 'Failed to schedule verify_api_spec_files: ' . $@ );
    }
    return;
}

sub _ensure_dirs {
    mkdir( $Cpanel::AppConfig::APPCONF_DIR, 0755 ) if !-e $Cpanel::AppConfig::APPCONF_DIR;
    return 1;
}

sub _get_conf_path {
    my ( $self, $app ) = @_;

    if ( $app !~ m/^[a-zA-Z0-9_-]+$/ ) {
        return ( 0, "App names ($app) may only contain letters, numbers, - and _" );
    }

    return ( 1, "$Cpanel::AppConfig::APPCONF_DIR/$app.conf" );

}

sub _reset_whostmgr_plugin_cache {
    Whostmgr::Plugins::update_cache();
    Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();
    return 1;
}

sub _reload_cpsrvd {

    # will always succeed unless the system is broken
    Cpanel::Signal::send_hup_cpsrvd();

    return 1;
}

sub _process_appconfig {
    my ( $config, $original_config_file_path ) = @_;

    if ( !$config ) {
        return ( 0, "_process_appconfig requires config text" );
    }

    my $temp_obj         = Cpanel::TempFile->new();
    my $temp_config_file = $temp_obj->file();

    if ( !$temp_config_file ) {
        return ( 0, "Failed to generate a temp file." );
    }

    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $temp_config_file, $config, 0600 ) ) {
        return ( 0, "Failed to write to temp file: $temp_config_file: $!" );
    }

    my $empty_appconfig_copy = Cpanel::AdminBin::Serializer::clone($empty_appconfig);

    my ( $appconfig_status, $appconfig_statusmsg ) = Cpanel::AppConfig::process_appconfig_file( $temp_config_file, $empty_appconfig_copy, $original_config_file_path );

    return ( $appconfig_status, $appconfig_statusmsg, $empty_appconfig_copy );
}

sub _find_service_with_appconfig {
    my ($appref) = @_;
    my $service;

    # Find which service the appconfig is for
    foreach my $check_service ( keys %{$appref} ) {
        if ( @{ $appref->{$check_service} } ) {
            $service = $check_service;
            last;
        }
    }
    return $service;
}

1;
