package Whostmgr::API::1::CPSCServices;

# cpanel - Whostmgr/API/1/CPSCServices.pm          Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::CPSCServices

=head1 SYNOPSIS

whmapi1 cpsc_get_config service=$service

whmapi1 cpsc_set_config service=$service key=value ...

whmapi1 cpsc_deploy service=$service

whmapi1 cpsc_update service=$service key=value ...

whmapi1 cpsc_remove service=$service

=head1 DESCRIPTION

This module exposes APIs for interaction with Services running in cPanel & WHM’s Services Cluster

=cut

#----------------------------------------------------------------------

use Cpanel::Pkgr                       ();
use Cpanel::Locale                     ();
use Cpanel::Logger                     ();
use Cpanel::OS                         ();
use Cpanel::SysPkgs                    ();
use Cpanel::ProcessLog::WithChildError ();
use Whostmgr::API::1::Utils            ();

use constant NEEDS_ROLE => {
    get_config           => 'CloudController',
    set_config           => 'CloudController',
    do_deployment        => 'CloudController',
    update_deployment    => 'CloudController',
    remove_deployment    => 'CloudController',
    install_base_package => 'CloudController',
    remove_base_package  => 'CloudController',
};

use constant BASE_DIR        => '/etc/cpanel/services-cluster';
use constant PUBLIC_KEY_PATH => BASE_DIR . '/CPSCPublicPkgKey.asc';
use constant LOGDIR          => '/var/log/cpanel-services-cluster';

my $service_info = {
    database => {
        package => 'cpsc-service-database',
        module  => 'CPSC::Service::Database',
        pm      => 'CPSC/Service/Database.pm'
    },
    dns => {
        package => 'cpsc-service-dns',
        module  => 'CPSC::Service::DNS',
        pm      => 'CPSC/Service/DNS.pm',
    },
    'k3s' => {
        package => 'cpsc-core-k3s',
        module  => 'CPSC::Orch::k3s',
        pm      => 'CPSC/Orch/k3s.pm',
    },
};

my $locale;

=head1 FUNCTIONS

=head2 get_config

Returns the config of a service.

The config can be an arbitrary list of key/value pairs. The valid config keys are dependent on the service.

These configs are currently stored at /etc/cpanel/services-cluster/$service/service.conf

=cut

sub get_config ( $args, $metadata, $ ) {

    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );

    local @INC = _fix_inc();
    return if !_preflight_checks( $metadata, $service );

    my ( $err, %config );

    try {
        my $srv = $service_info->{$service}{'module'}->instance();
        %config = $srv->get_config->%*;
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $metadata->set_not_ok($err);
        return;
    }

    $metadata->set_ok();
    return {%config};
}

=head2 set_config

Updates the config of a service. Returns the newly updated config.

The config can be an arbitrary list of key/value pairs. The valid config keys are dependent on the service.

These configs are currently stored at /etc/cpanel/services-cluster/$service/service.conf

=cut

sub set_config ( $args, $metadata, $ ) {

    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );

    local @INC = _fix_inc();
    return if !_preflight_checks( $metadata, $service );

    my ( $err, %config );

    try {
        %config = _update_conf( $args, $service );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $metadata->set_not_ok($err);
        return;
    }

    $metadata->set_ok();
    return {%config};
}

=head2 install_base_package

This method installs the service package to the system.

Returns:

logfile -- A logfile of the package transaction.

=cut

sub install_base_package ( $args, $metadata, $ ) {

    require Cpanel::HTTP::Tiny::FastSSLVerify;

    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );
    my $package = $service_info->{$service}{'package'};

    my ( $logfile, $logger ) = _setup_logger('cpsc_pkg_install');

    my $sysp = Cpanel::SysPkgs->new( output_obj => $logger );
    my $err;

    _init_locale();

    if ( _base_package_installed($service) ) {
        $metadata->set_not_ok( $locale->maketext( 'The package “[_1]” is already installed.', $package ) );
        return { logfile => $logfile };
    }

    if ( !-f Cpanel::OS::cpsc_from_bare_repo_path() ) {
        try {
            $sysp->add_repo( local_path => Cpanel::OS::cpsc_from_bare_repo_path(), remote_path => Cpanel::OS::cpsc_from_bare_repo_url() );
        }
        catch {
            $err = $_;
        };
        if ($err) {
            $metadata->set_not_ok( $locale->maketext( 'Failed to add repository to package manager: “[_1]”.', $err ) );
            return { logfile => $logfile };
        }
    }

    return if !_add_repo_key($metadata);

    my $out = $sysp->install_packages( packages => [$package] );
    if ( !$out ) {
        $metadata->set_not_ok( $locale->maketext( 'The package “[_1]” failed to install: “[_2]”.', $package, $sysp->error() ) );
    }
    else {
        $metadata->set_ok();
    }

    return { logfile => $logfile };
}

=head2 remove_base_package

This method removes the service package from the system.

The package removal will be blocked if the service is currently deployed to a cluster.

Returns:

logfile -- A logfile of the package transaction.

=cut

sub remove_base_package ( $args, $metadata, $ ) {

    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );
    my $package = $service_info->{$service}{'package'};

    _init_locale();

    if ( !_base_package_installed($service) ) {
        $metadata->set_not_ok( $locale->maketext( 'The package “[_1]” must be installed first.', $package ) );
        return;
    }

    local @INC = _fix_inc();
    return if !_preflight_checks( $metadata, $service );

    my $srv = $service_info->{$service}{'module'}->instance();

    if ( $srv->can('deployment_touchfile') && -e $srv->deployment_touchfile() ) {
        $metadata->set_not_ok( $locale->maketext( 'A [_1] [_2] service is currently deployed. You must remove the service before removing this package.', 'cPCloud', $service ) );
        return;
    }

    my ( $logfile, $logger ) = _setup_logger('cpsc_pkg_remove');
    my $sysp = Cpanel::SysPkgs->new( output_obj => $logger );
    my $out  = $sysp->uninstall_packages( packages => [$package] );
    if ( !$out ) {
        $metadata->set_not_ok( $locale->maketext( 'The package “[_1]” failed to uninstall: “[_2]”.', $package, $sysp->error() ) );
    }
    else {
        $metadata->set_ok();
    }

    return { logfile => $logfile };

}

=head2 do_deployment

Starts the deployment of a service based on the service configuration that is set.

Returns:

logfile -- A logfile of the deployment.

pid -- The pid of the process running the deployment.

logentry -- A string that can be used for sending the log to a websocket.

=cut

sub do_deployment ( $args, $metadata, $ ) {

    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );

    local @INC = _fix_inc();
    return if !_preflight_checks( $metadata, $service );

    my $srv = $service_info->{$service}{'module'}->instance();

    if ( $srv->can('deployment_touchfile') && -e $srv->deployment_touchfile() ) {
        $metadata->set_not_ok( $locale->maketext( 'A [_1] [_2] service is already deployed. The deployment touchfile, “[_3]”, exists.', 'cPCloud', $service, $srv->deployment_touchfile() ) );
        return;
    }

    return _do_action( $srv, $service, $metadata, 'deploy' );
}

=head2 update_deployment

Updates a deployment of a service based on the service configuration that is set. Changes to the configuration can be passed in as arguments. The configuration will be updated.

Returns:

logfile -- A logfile of the update.

pid -- The pid of the process running the update.

logentry -- A string that can be used for sending the log to a websocket.

=cut

sub update_deployment ( $args, $metadata, $ ) {

    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );

    local @INC = _fix_inc();
    return if !_preflight_checks( $metadata, $service );

    my ( $err, %config );

    try {
        %config = _update_conf( $args, $service );
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $metadata->set_not_ok($err);
        return;
    }

    my $srv = $service_info->{$service}{'module'}->instance();

    if ( $srv->can('deployment_touchfile') && !-e $srv->deployment_touchfile() ) {
        $metadata->set_not_ok( $locale->maketext( 'A [_1] [_2] service is not deployed. The deployment touchfile, “[_3]”, does not exist.', 'cPCloud', $service, $srv->deployment_touchfile() ) );
        return;
    }

    return _do_action( $srv, $service, $metadata, 'update' );
}

=head2 remove_deployment

Removes a deployment.

Returns:

logfile -- The log file of the removal.

pid -- The pid of the process running the removal.

logentry -- A string that can be used for sending the log to a websocket.

=cut

sub remove_deployment ( $args, $metadata, $ ) {

    my $service = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'service' );

    local @INC = _fix_inc();
    return if !_preflight_checks( $metadata, $service );

    my $srv = $service_info->{$service}{'module'}->instance();

    if ( $srv->can('deployment_touchfile') && !-e $srv->deployment_touchfile() ) {
        $metadata->set_not_ok( $locale->maketext( 'A [_1] [_2] service is not deployed. The deployment touchfile, “[_3]”, does not exist.', 'cPCloud', $service, $srv->deployment_touchfile() ) );
        return;
    }

    return _do_action( $srv, $service, $metadata, 'teardown' );
}

sub _add_repo_key ($metadata) {
    my $repo_key_url = Cpanel::OS::cpsc_from_bare_repo_key_url();
    return 1 unless $repo_key_url;    # not every OS has a repo key to add

    require Cpanel::Mkdir;

    my $err;
    try {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( BASE_DIR, 0755 );
    }
    catch {
        $err = $_;
    };
    if ($err) {
        $metadata->set_not_ok( $locale->maketext( 'The system attempted to create a directory “[_1]” to save an authentication key, but the system failed to create this directory because of an error: [_2]', BASE_DIR, $err ) );
        return 0;
    }

    my $http = Cpanel::HTTP::Tiny::FastSSLVerify->new();
    my $resp = $http->mirror( $repo_key_url, PUBLIC_KEY_PATH );

    if ( !$resp->{success} ) {
        $metadata->set_not_ok( $locale->maketext( 'The system attempted to mirror an authentication key but failed: “[_1]”.', $resp ) );
        return 0;
    }

    try {
        Cpanel::SysPkgs->new()->add_repo_key(PUBLIC_KEY_PATH);
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $metadata->set_not_ok( $locale->maketext( 'The system attempted to add an authentication key to the package manager but failed: [_1]', $err ) );
        return 0;
    }

    return 1;
}

sub _do_action ( $srv, $service, $metadata, $action ) {

    if ( $service_info->{$service}{'module'} =~ /^CPSC::Orch/ ) {
        $action = "orch_$action";
    }

    if ( $srv->can('pidfile') && -e $srv->pidfile() ) {
        $metadata->set_not_ok( $locale->maketext( 'A [_1] [_2] action is already in progress. Pid file exists: [_3]', 'cPCloud', $service, $srv->pidfile() ) );
        return;
    }

    if ( $srv->can($action) ) {

        my ( $log, $log_entry ) = _create_logging_stream_dir( "cpsc_" . $service . "_" . $action );
        symlink( $srv->logfile(), $log );

        my $out = $srv->can($action)->($srv);
        $metadata->set_ok();
        return { $out->%*, 'log_entry' => $log_entry };
    }

    $metadata->set_not_ok( $locale->maketext( 'Unable to [_2] the “[_1]” service. No “[_2]” method exists.', $service, $action ) );
    return;

}

sub _update_conf ( $args, $service ) {

    my $srv = $service_info->{$service}{'module'}->instance();

    my $confs = $srv->conf_keys();
    my %new;

    foreach my $conf ( $confs->@* ) {
        $new{$conf} = $args->{$conf} if defined $args->{$conf};
    }

    my %config = $srv->get_config->%*;

    foreach my $key ( keys %new ) {
        $config{$key} = $new{$key};
    }

    $srv->set_config_global( \%config );

    return $srv->get_config->%*;

}

sub _fix_inc {
    return ( '/opt/cpanel/services-cluster/lib', @INC );
}

sub _ensure_base_package_installed ( $metadata, $service ) {

    if ( !Cpanel::Pkgr::is_installed( $service_info->{$service}{'package'} ) ) {
        $metadata->set_not_ok( $locale->maketext( 'The package “[_1]” must be installed first.', $service_info->{$service}{'package'} ) );
        return 0;
    }

    return 1;
}

sub _base_package_installed ($service) {

    if ( Cpanel::Pkgr::is_installed( $service_info->{$service}{'package'} ) ) {
        return 1;
    }

    return 0;
}

sub _ensure_module_load ( $metadata, $service ) {

    my $err;

    try {
        require "$service_info->{$service}{pm}";
    }
    catch {
        $err = $_;
    };

    if ($err) {
        $metadata->set_not_ok( $locale->maketext( "Failed to load the “[_1]” module: [_2]", $service_info->{$service}{pm}, $err ) );
        return;
    }

    return 1;
}

sub _init_locale {
    require Cpanel::Locale;
    $locale ||= Cpanel::Locale->get_handle();
    return;
}

sub _create_logging_stream_dir ($name) {
    my $log_entry = Cpanel::ProcessLog::WithChildError->create_new( $name, 'CHILD_ERROR' => '?' );
    my $log_dir   = Cpanel::ProcessLog::WithChildError::_DIR();
    my $log       = "$log_dir/$log_entry/txt";
    unlink $log;
    return ( $log, $log_entry );
}

sub _is_valid_service ( $metadata, $service ) {
    if ( !$service_info->{$service} ) {
        $metadata->set_not_ok( $locale->maketext( "“[_1]” is not a valid CPSC service. The valid services are [list_and_quoted,_2].", $service, [ keys $service_info->%* ] ) );
        return;
    }
    return 1;
}

sub _preflight_checks ( $metadata, $service ) {
    _init_locale();
    return if !_is_valid_service( $metadata, $service );
    return if !_ensure_base_package_installed( $metadata, $service );
    return if !_ensure_module_load( $metadata, $service );
    return 1;
}

sub _setup_logger ( $name = 'cpsc' ) {
    require DateTime;
    my $logfile = LOGDIR . "/" . $name . "_" . DateTime->now->datetime . ".log";
    my $logger  = Cpanel::Logger->new( { alternate_logfile => $logfile } );
    return ( $logfile, $logger );
}

1;
