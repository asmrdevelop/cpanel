package Cpanel::Init::Enable::Systemd;

# cpanel - Cpanel/Init/Enable/Systemd.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Moo;
use cPstrict;

use Cpanel::SafeRun::Errors     ();
use Cpanel::RestartSrv::Systemd ();
use Cpanel::FileUtils::Dir      ();
use Cpanel::JSON                ();    # PPI USE OK - needed for LoadConfig
use Cpanel::Config::LoadConfig  ();

extends 'Cpanel::Init::Enable::Initd';

has 'systemctl' => ( is => 'rw', default => q{/usr/bin/systemctl} );

our $SERVICE_PATH = '/etc/systemd/system';

sub collect_enable {
    my ( $self, $service ) = @_;

    $self->SUPER::collect_enable($service);

    my $subservices = $self->_get_subservices_for($service) || [];
    foreach my $subservice (@$subservices) {
        $self->SUPER::collect_enable($subservice);
    }

    return;
}

sub collect_disable {
    my ( $self, $service ) = @_;

    $self->SUPER::collect_disable($service);

    my $subservices = $self->_get_subservices_for($service) || [];
    foreach my $subservice (@$subservices) {
        $self->SUPER::collect_disable($subservice);
    }

    return;
}

sub _get_subservices_for {
    my ( $self, $service ) = @_;

    return [] unless $service;

    my $dir_nodes_ar = Cpanel::FileUtils::Dir::get_directory_nodes($SERVICE_PATH);
    my @subservices;
    foreach my $node (@$dir_nodes_ar) {
        next if !$self->{'service_cache'}{$node} && -d "$SERVICE_PATH/$node";

        # get services from /etc/systemd/system/ ( cPanel only install services there )
        my $conf = ( $self->{'service_cache'}{$node} ||= scalar Cpanel::Config::LoadConfig::loadConfig( "$SERVICE_PATH/$node", (undef) x 5, { 'delimiter' => '=', 'use_hash_of_arr_refs' => 1 } ) );
        if ( $conf->{'PartOf'} ) {
            foreach my $part ( @{ $conf->{'PartOf'} } ) {
                if ( $part =~ m{^\Q$service\E\.service$} ) {
                    push @subservices, $node;
                }
            }
        }
    }
    return \@subservices;
}

sub enable {
    my ( $self, $levels ) = @_;
    my $to_enable = $self->enabled;
    my $systemctl = $self->systemctl;

    # preserve the original behavior to stop when the first fails
    foreach my $service ( @{$to_enable} ) {
        if ( my $info = Cpanel::RestartSrv::Systemd::has_service_via_systemd($service) ) {
            next if $self->is_enabled( $service, $info );    # enable is slow, lets not do it if its already enabled
            Cpanel::SafeRun::Errors::saferunnoerror( $systemctl, 'enable', $service );
            return 0 if !$self->is_enabled($service);
        }
        else {
            # we only want to enable this service
            local $self->{'enabled'} = [$service];
            return 0 if !$self->SUPER::enable($levels);
        }
    }

    return 1;
}

sub disable {
    my ( $self, $levels ) = @_;
    my $to_disabled = $self->disabled;
    my $systemctl   = $self->systemctl;

    foreach my $service ( @{$to_disabled} ) {
        if ( my $info = Cpanel::RestartSrv::Systemd::has_service_via_systemd($service) ) {
            next if !$self->is_enabled( $service, $info );    # disable is slow, lets not do it unless its enabled
            Cpanel::SafeRun::Errors::saferunnoerror( $systemctl, 'disable', $service );
            return 0 if $self->is_enabled($service);
        }
        else {
            # we only want to disable this service
            local $self->{'disabled'} = [$service];
            return 0 if !$self->SUPER::disable($levels);
        }
    }

    return 1;
}

#overridden in tests
*_get_systemd_info = \*Cpanel::RestartSrv::Systemd::has_service_via_systemd;

sub is_enabled {
    my ( $self, $service, $info ) = @_;

    $info ||= _get_systemd_info($service);

    if ( !$info ) {
        return $self->SUPER::is_enabled($service);
    }

    return 0 if !$info;
    return 0 if $info->{'LoadState'} ne 'loaded';

    # “enabled” means it’s explicitly enabled; “static” means that
    # something else depends on it, i.e., it’s “implicitly” enabled.
    # cf: https://bbs.archlinux.org/viewtopic.php?id=147964
    return 0 if !grep { $info->{'UnitFileState'} eq $_ } ( 'enabled', 'static' );

    return 1;
}

sub daemon_reload {
    my ($self) = @_;

    return Cpanel::SafeRun::Errors::saferunnoerror( $self->systemctl, 'daemon-reload' );
}

1;
