package Cpanel::ServiceManager::Services::Cphulkd;

# cpanel - Cpanel/ServiceManager/Services/Cphulkd.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Hot ();    # PPI USE OK - extends
extends 'Cpanel::ServiceManager::Hot';

use Cpanel::Exception    ();
use Cpanel::Config::Hulk ();

has '+is_cpanel_service' => ( is => 'ro', default => 1 );
has '+pidfile'           => ( is => 'ro', default => '/var/run/cphulkd_processor.pid' );
has '+service_binary'    => ( is => 'ro', default => '/usr/local/cpanel/cphulkd' );
has '+suspend_time'      => ( is => 'ro', default => 30 );

has '+pid_exe'       => ( is => 'ro', lazy => 1, default => sub { qr{^(/usr/local/cpanel/3rdparty/perl/[0-9]+/bin/perl|/usr/local/cpanel/libexec/cphulkd-dormant)$} } );
has '+doomed_rules'  => ( is => 'ro', lazy => 1, default => sub { ['cPhulkd'] } );
has '+startup_args'  => ( is => 'ro', lazy => 1, default => sub { [ qw{ --start }, $_[0]->service_manager()->this_process_was_executed_by_systemd() ? q{--systemd} : () ] } );
has '+shutdown_args' => ( is => 'ro', lazy => 1, default => sub { [qw{ --stop }] } );
has '+is_configured' => ( is => 'rw', lazy => 1, default => sub { Cpanel::Config::Hulk::is_enabled() } );

sub check {
    my $self = shift;

    return 0 if !$self->SUPER::check(@_);

    # The closely related $Cpanel::Config::Hulk::dbsocket is checked in Cpanel::Hulkd::main_loop
    if ( !-S $Cpanel::Config::Hulk::socket ) {
        die Cpanel::Exception::create( 'Services::SocketIsMissing', [ service => $self->service, socket => $Cpanel::Config::Hulk::socket ] );
    }
    return 1;
}

1;
