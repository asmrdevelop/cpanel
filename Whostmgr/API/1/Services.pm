package Whostmgr::API::1::Services;

# cpanel - Whostmgr/API/1/Services.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule          ();
use Cpanel::Chkservd::Manage    ();
use Cpanel::Services::List      ();
use Cpanel::Services::Enabled   ();
use Cpanel::Services::Installed ();
use Cpanel::Services::Restart   ();
use Whostmgr::API::1::Utils     ();
use Whostmgr::Services          ();

use constant NEEDS_ROLE => {
    configureservice                    => undef,
    enable_monitor_all_enabled_services => undef,
    restartservice                      => undef,
    servicestatus                       => undef,
};

my $MONITORED_SERVICES;

sub _populate_service_configuration {
    my $service = shift;
    my $name    = $service->{'name'};
    $MONITORED_SERVICES ||= Cpanel::Chkservd::Manage::getmonitored();

    my $enabled   = Cpanel::Services::Enabled::is_enabled($name);
    my $monitored = $MONITORED_SERVICES->{$name};

    if ( $name eq 'exim-altport' ) {
        my $clean_service = Cpanel::Services::List::canonicalize_service( $name, $enabled, $MONITORED_SERVICES );
        $service->{'monitored'} = $clean_service->{'monitored'};
        $service->{'settings'}  = $clean_service->{'settings'};
    }
    else {
        $service->{'monitored'} = $monitored ? 1 : 0;
    }

    $service->{'enabled'}   = $enabled                                                 ? 1 : 0;
    $service->{'installed'} = Cpanel::Services::Installed::service_is_installed($name) ? 1 : 0;

    if ( $enabled && $monitored ) {
        $service->{'running'} = Whostmgr::Services::is_running($name) ? 1 : 0;
    }

    return 1;
}

sub enable_monitor_all_enabled_services {
    my ( $args, $metadata ) = @_;
    require Cpanel::Services;
    my $results = Cpanel::Services::monitor_enabled_services();
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { 'services' => $results };
}

sub servicestatus {
    my ( $args, $metadata ) = @_;
    my $service_name = $args->{'service'};
    my $services     = Cpanel::Services::List::get_service_list();
    my @service_list;
    if ( exists $args->{'service'} && exists $services->{$service_name} ) {
        my $display_name = $services->{$service_name}->{'name'};
        push @service_list, { 'name' => $service_name, 'display_name' => $display_name };
    }
    elsif ( exists $args->{'service'} ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Specified service does not exist.';
        return;
    }
    else {
        foreach my $name ( sort keys %$services ) {
            my $display_name = $services->{$name}->{'name'};
            push @service_list, { 'name' => $name, 'display_name' => $display_name };
        }
    }

    foreach my $service (@service_list) {
        _populate_service_configuration($service);
    }

    $metadata->{'result'} = 1;
    $metadata->{'reason'} = 'OK';
    return { 'service' => \@service_list };
}

sub _set_service_monitored {
    my $service_name = shift;
    my $monitored    = shift;

    if ( $monitored !~ m/^[01]{1}$/ ) {
        return 0, 'Invalid parameter specified for monitoring.';
    }

    if ( $monitored eq '1' ) {
        if ( Cpanel::Chkservd::Manage::enable($service_name) ) {
            return 1, "Enabled monitoring for $service_name.";
        }
        else {
            return 0, "Failed to enable monitoring for $service_name.";
        }
    }
    else {
        if ( Cpanel::Chkservd::Manage::disable($service_name) ) {
            return 1, "Disabled monitoring for $service_name.";
        }
        else {
            return 0, "Failed to disable monitoring for $service_name.";
        }
    }

    return;
}

sub _set_service_enabled {
    my $service_name = shift;
    my $enabled      = shift;
    my $result;
    my $msg;

    if ( $enabled !~ m/^[01]{1}$/ ) {
        return 0, 'Invalid parameter specified for monitoring.';
    }

    if ( $enabled eq '1' ) {
        ( $result, $msg ) = Whostmgr::Services::enable($service_name);
        if ($result) {
            return 1, "Enabled $service_name.";
        }
        else {
            return 0, "Failed to enable $service_name.\n$msg";
        }
    }
    else {
        ( $result, $msg ) = Whostmgr::Services::disable($service_name);
        if ($result) {
            return 1, "Disabled $service_name.";
        }
        else {
            return 0, "Failed to disable $service_name.\n$msg";
        }
    }

    return;
}

sub configureservice {
    my ( $args, $metadata ) = @_;

    # Deny cluster ACL from configuring anything but 'named'
    # If we got here *without* the restartservice ACL, then must be clustering
    my $servicename = $args->{service} || '';
    if ( $servicename ne 'named' ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        die "Clustering ACL only allows configuration of named" unless Whostmgr::ACLS::hasroot();
    }

    if ( $servicename eq 'cpdavd' ) {
        require Cpanel::ServiceConfig::cpdavd;
        Cpanel::ServiceConfig::cpdavd::die_if_unneeded();
    }

    require Cpanel::Server::Type::Profile::Roles;
    require Cpanel::Services::Installed::State;
    my $services          = Cpanel::Services::List::get_service_list();
    my $all_service_names = Cpanel::Services::Installed::State::get_handled_services();
    my %extra_services    = map { $_ => 1 } @{ $all_service_names->{'extra_services'} };

    if (
        !exists $args->{'service'} ||    #
        ( !exists $services->{ $args->{'service'} } && !exists $extra_services{ $args->{'service'} } )
    ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Specified service does not exist or was not specified.';
    }
    elsif ( !Cpanel::Server::Type::Profile::Roles::is_service_allowed( $args->{'service'} ) ) {
        $metadata->{'result'} = 0;
        $metadata->{'reason'} = 'Specified service is not available on this server.';
    }
    elsif ( !exists $args->{'enabled'} && !exists $args->{'monitored'} ) {
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'No changes made.';
    }
    elsif ( $args->{'service'} eq 'exim-altport' ) {
        my ( $result, $reason ) = _configure_exim_altport($args);
        $metadata->{'result'} = $result;
        $metadata->{'reason'} = $result ? 'OK' : $reason;
        if ($result) {
            restartservice( { 'service' => 'exim' }, $metadata );
        }
    }
    else {
        my $name                        = $args->{'service'};
        my $failed_to_enable_or_disable = 0;
        my $enabled                     = Cpanel::Services::Enabled::is_enabled($name) ? 1 : 0;
        my $result;
        my $reason;

        if ( exists $args->{'enabled'} && $args->{'enabled'} != $enabled ) {
            ( $result, $reason ) = _set_service_enabled( $name, $args->{'enabled'} );

            if ( !$result ) {
                $failed_to_enable_or_disable = 1;
            }
        }

        if ( !$failed_to_enable_or_disable && exists $args->{'monitored'} ) {
            my $tmp_reason;
            ( $result, $tmp_reason ) = _set_service_monitored( $name, $args->{'monitored'} );
            if ( length $reason ) {
                $reason = length $tmp_reason ? $reason . ' ' . $tmp_reason : $reason;
            }
            else {
                $reason = $tmp_reason;
            }
        }

        if ( !defined $result ) {
            $metadata->{'result'} = 1;
            $metadata->{'reason'} = 'No changes made.';
        }
        else {
            $metadata->{'result'} = $result ? 1 : 0;
            $metadata->{'reason'} = $reason || ( $result ? 'OK' : 'Failed to configure service.' );
        }
    }

    return;
}

sub _configure_exim_altport {
    my ($args) = @_;

    Cpanel::LoadModule::load_perl_module('Whostmgr::Exim::Config');
    Cpanel::LoadModule::load_perl_module('Whostmgr::Services::exim_altport');

    my $controls_ref = {
        'exim-altport'        => $args->{'enabled'},
        'exim-altportmonitor' => $args->{'monitored'},
        'exim-altportnum'     => $args->{'exim-altportnum'},
    };

    my %monitored_ports;
    my %unmonitored_ports;

    my ( $configured_ok, $msg, $need_to_rebuild_exim_conf ) = Whostmgr::Services::exim_altport::configure( $controls_ref, \%monitored_ports, \%unmonitored_ports );

    if ( !$configured_ok ) {
        return ( 0, $msg );
    }

    my $status    = 1;
    my $statusmsg = '';
    my $html;
    if ($need_to_rebuild_exim_conf) {
        ( $status, $statusmsg, $html ) = Whostmgr::Exim::Config::attempt_exim_config_update();
    }
    if ( exists $args->{'monitored'} ) {
        foreach my $ports ( keys %monitored_ports ) {
            my $tmp_reason;
            ( $status, $tmp_reason ) = _set_service_monitored( $ports, $args->{'monitored'} );
            if ( length $statusmsg ) {
                $statusmsg = length $tmp_reason ? $statusmsg . ' ' . $tmp_reason : $statusmsg;
            }
            else {
                $statusmsg = $tmp_reason;
            }
        }
    }
    foreach my $ports ( keys %unmonitored_ports ) {
        my $tmp_reason;
        ( $status, $tmp_reason ) = _set_service_monitored( $ports, 0 );
        if ( length $statusmsg ) {
            $statusmsg = length $tmp_reason ? $statusmsg . ' ' . $tmp_reason : $statusmsg;
        }
        else {
            $statusmsg = $tmp_reason;
        }
    }

    return ( $status, $statusmsg );
}

sub restartservice {
    my ( $args, $metadata ) = @_;
    my $service     = $args->{'service'} || '';
    my $queue       = $args->{queue_task};
    my $servicelist = Cpanel::Services::List::get_service_list();
    my $servicename = $servicelist->{$service}->{'name'} || '';
    my $output;

    # Deny cluster ACL from restarting anything but 'named'
    # If we got here *without* the restartservice ACL, then must be clustering
    if ( $service ne 'named' ) {
        require Whostmgr::ACLS;
        Whostmgr::ACLS::init_acls();
        die "Clustering ACL only allows restart of named" unless Whostmgr::ACLS::checkacl('restart');
    }

    if ($servicename) {
        if ($queue) {
            require Cpanel::ServerTasks;
            $output = Cpanel::ServerTasks::queue_task( ['CpServicesTasks'], "restartsrv $service" );
            $metadata->set_ok();
            return { 'service' => $service };
        }

        my $graceful = $service eq 'cpsrvd' ? 1 : 0;
        $output = Cpanel::Services::Restart::restartservice( $service, undef, undef, undef, $graceful );
        if ( $? || $output =~ m/ has failed/ ) {
            $metadata->set_not_ok('Failed to restart service.');
        }
        else {
            $metadata->set_ok();
        }
        if ( length $output ) {
            $metadata->{'output'}->{'raw'} = $output;
        }
        $metadata->set_ok();
        return { 'service' => $service };
    }
    else {
        $metadata->set_not_ok('No such service');
    }

    return {};
}

1;

__END__
