package Cpanel::ServiceManager::Services::Queueprocd;

# cpanel - Cpanel/ServiceManager/Services/Queueprocd.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Hot ();    # PPI USE OK - extends
extends 'Cpanel::ServiceManager::Hot';

has '+is_cpanel_service'   => ( is => 'ro', default => 1 );
has '+pidfile'             => ( is => 'ro', default => '/var/run/queueprocd.pid' );
has '+service_binary'      => ( is => 'ro', default => '/usr/local/cpanel/libexec/queueprocd' );
has '+suspend_time'        => ( is => 'ro', default => 30 );
has '+block_fresh_install' => ( is => 'ro', default => 1 );

has '+doomed_rules'  => ( is => 'ro', lazy => 1, default => sub { ['queueprocd'] } );
has '+startup_args'  => ( is => 'ro', lazy => 1, default => sub { [ qw{ --start }, $_[0]->service_manager()->this_process_was_executed_by_systemd() ? q{--systemd} : () ] } );
has '+shutdown_args' => ( is => 'ro', lazy => 1, default => sub { [qw{ --stop }] } );

1;
