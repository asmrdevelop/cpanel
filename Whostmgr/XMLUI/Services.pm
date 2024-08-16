package Whostmgr::XMLUI::Services;

# cpanel - Whostmgr/XMLUI/Services.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Services::List      ();
use Whostmgr::XMLUI             ();
use Whostmgr::ApiHandler        ();
use Cpanel::Services::Enabled   ();
use Cpanel::Services::Installed ();
use Cpanel::Services::Restart   ();
use Cpanel::LoadModule          ();
use Whostmgr::Services          ();

my $MONITORED_SERVICES;

sub _populate_service_configuration {
    my $service = shift;
    Cpanel::LoadModule::load_perl_module('Cpanel::Chkservd::Manage');
    my $name = $service->{'name'};
    $MONITORED_SERVICES ||= Cpanel::Chkservd::Manage::getmonitored();

    my $enabled   = Cpanel::Services::Enabled::is_enabled($name);
    my $monitored = $MONITORED_SERVICES->{$name};
    $service->{'enabled'}   = $enabled                                                 ? 1 : 0;
    $service->{'monitored'} = $monitored                                               ? 1 : 0;
    $service->{'installed'} = Cpanel::Services::Installed::service_is_installed($name) ? 1 : 0;

    if ( $enabled && $monitored ) {
        $service->{'running'} = Whostmgr::Services::is_running($name) ? 1 : 0;
    }

    return 1;
}

sub status {
    my %OPTS = @_;
    my @RSD;
    my $services = Cpanel::Services::List::get_service_list();
    my $msg;

    if ( exists $OPTS{'service'} && exists $services->{ $OPTS{'service'} } ) {
        my $name         = $OPTS{'service'};
        my $display_name = $services->{$name}->{'name'};
        push @RSD, { 'name' => $name, 'display_name' => $display_name };
    }
    elsif ( exists $OPTS{'service'} ) {
        $msg = 'Specified service does not exist.';
    }
    else {
        foreach my $name ( sort keys %$services ) {
            my $display_name = $services->{$name}->{'name'};
            push @RSD, { 'name' => $name, 'display_name' => $display_name };
        }
    }

    foreach my $service (@RSD) {
        _populate_service_configuration($service);
    }

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'service'} = \@RSD;
    $RS{'result'}  = { status => defined $msg ? 0 : 1, statusmsg => $msg };
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'servicestatus', NoAttr => 1 );
}

sub _set_service_monitored {
    my $service_name = shift;
    my $monitored    = shift;

    Cpanel::LoadModule::load_perl_module('Cpanel::Chkservd::Manage');
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

sub configure {
    my %OPTS     = @_;
    my $services = Cpanel::Services::List::get_service_list();
    my $result;
    my $msg;

    if ( !exists $OPTS{'service'} || !exists $services->{ $OPTS{'service'} } ) {
        $result = 0;
        $msg    = 'Specified service does not exist or was not specified.';
    }
    elsif ( !exists $OPTS{'enabled'} && !exists $OPTS{'monitored'} ) {
        $result = 1;
        $msg    = 'No changes made.';
    }
    else {
        my $name                        = $OPTS{'service'};
        my $failed_to_enable_or_disable = 0;
        my $enabled                     = Cpanel::Services::Enabled::is_enabled($name) ? 1 : 0;

        if ( exists $OPTS{'enabled'} && $OPTS{'enabled'} != $enabled ) {
            ( $result, $msg ) = _set_service_enabled( $name, $OPTS{'enabled'} );

            if ( !$result ) {
                $failed_to_enable_or_disable = 1;
            }
        }

        if ( !$failed_to_enable_or_disable && exists $OPTS{'monitored'} ) {
            my $tmp_msg;
            ( $result, $tmp_msg ) = _set_service_monitored( $name, $OPTS{'monitored'} );

            if ( defined $msg ) {
                $msg .= '  ';
            }

            $msg .= $tmp_msg;
        }
    }

    if ( !defined $result ) {
        $result = 1;
        $msg    = 'No changes made.';
    }

    my @RSD;
    push @RSD, { status => $result, statusmsg => $msg };

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS = ( 'result' => \@RSD );
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'configureservice', NoAttr => 1 );
}

sub restart {
    my %OPTS        = @_;
    my $service     = $OPTS{'service'};
    my $servicelist = Cpanel::Services::List::get_service_list();

    my $result = 1;
    my $resout;
    my $servicename;
    if ( !length $service ) {
        $servicename = 'restart requires the “service” parameter.';
        $result      = 0;
    }
    else {
        $servicename = exists $servicelist->{$service} ? $servicelist->{$service}->{'name'} : '';
        if ($servicename) {
            $resout = Cpanel::Services::Restart::restartservice($service);
            if ( $? || $resout =~ m/ has failed/ ) {
                $result = 0;
            }
        }
        else {
            $servicename = 'No such service';
            $result      = 0;
        }
    }

    my @RSD = ( { 'service' => $service, 'servicename' => $servicename, 'result' => $result, 'rawout' => $resout } );

    Whostmgr::XMLUI::xmlencode( \@RSD );

    my %RS;
    $RS{'restart'} = \@RSD;
    return Whostmgr::ApiHandler::out( \%RS, RootName => 'restartservice', NoAttr => 1 );
}

1;

__END__
