package Cpanel::ServiceManager::Services::Cpanel_php_fpm;

# cpanel - Cpanel/ServiceManager/Services/Cpanel_php_fpm.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Moo;

use Cpanel::Exception                   ();
use Cpanel::ServiceManager::Base        ();
use Cpanel::Server::FPM::Manager        ();
use Cpanel::Server::FPM::Manager::Check ();
use Cpanel::Kill::Single                ();

extends 'Cpanel::ServiceManager::Base';

has '+pidfile'            => ( is => 'ro', lazy => 1, default => sub { $Cpanel::Server::FPM::Manager::PID_FILE } );
has '+command_line_regex' => ( is => 'ro', lazy => 1, default => sub { qr/\Q$Cpanel::Server::FPM::Manager::SERVICE_PROCESS_NAME\E.*\Q$Cpanel::Server::FPM::Manager::CONFIG_FILE\E/ } );
has '+startup_args'       => ( is => 'ro', lazy => 1, default => sub { [ '-y', '/usr/local/cpanel/etc/php-fpm.conf' ] } );

has '+service_binary' => ( is => 'ro', default => '/usr/local/cpanel/3rdparty/sbin/cpanel_php_fpm' );
has '+suspend_time'   => ( is => 'ro', default => 30 );

has 'is_graceful_restart_enabled' => ( is => 'rw', default => 1 );

sub restart_gracefully {
    my ($self) = @_;

    return Cpanel::Server::FPM::Manager::checked_reload();
}

sub _kill_all_active_pids {
    my ($self) = @_;

    my $timeout     = 1;
    my @active_pids = Cpanel::Server::FPM::Manager::get_all_pids();
    foreach my $pid (@active_pids) {
        Cpanel::Kill::Single::safekill_single_pid( $pid, $timeout );
    }
    return;
}

sub stop {
    my ($self) = @_;

    $self->_kill_all_active_pids();
    return $self->SUPER::stop(@_);
}

sub start {
    my $self = shift;

    # CPANEL-25263 - if the master process crashes any pool processes
    # will remain, not reqlinquishing the socket, not allowing the
    # master process to restart.  Killing all pids should be cheap
    # and will clear all running pools.

    $self->_kill_all_active_pids();

    $self->rebuild_config();
    return $self->SUPER::start(@_);
}

sub rebuild_config {
    my ($self) = @_;

    return Cpanel::Server::FPM::Manager::sync_config_files();
}

sub _generate_start_exception {
    my ( $self, $exception_parameters ) = @_;

    die Cpanel::Exception::create( 'Services::StartError', 'The “[_1]” service failed to start. Check “[_2]” for more details.', [ $exception_parameters->{service}, $Cpanel::Server::FPM::Manager::ERROR_LOG ], $exception_parameters );
}

sub check {
    my ($self) = @_;
    return Cpanel::Server::FPM::Manager::Check->new()->check();
}

1;
