package Cpanel::ServiceManager::Services::Cpgreylistd;

# cpanel - Cpanel/ServiceManager/Services/Cpgreylistd.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Hot ();    # PPI USE OK - extends
use Cpanel::GreyList::Config    ();

extends 'Cpanel::ServiceManager::Hot';

has '+is_cpanel_service' => ( is => 'ro', default => 1 );
has '+service_binary'    => ( is => 'ro', default => '/usr/local/cpanel/cpgreylistd.pl' );
has '+suspend_time'      => ( is => 'ro', default => 30 );
has '+support_reload'    => ( is => 'ro', default => 1 );

has '+startup_args'  => ( is => 'ro', lazy => 1, default => sub { [ '--restart', $_[0]->service_manager()->this_process_was_executed_by_systemd() ? q{--systemd} : () ] } );
has '+shutdown_args' => ( is => 'ro', lazy => 1, default => sub { ['--stop'] } );
has '+restart_args'  => ( is => 'ro', lazy => 1, default => sub { ['--restart'] } );
has '+pidfile'       => ( is => 'ro', lazy => 1, default => sub { Cpanel::GreyList::Config::get_pid_file() } );
has '+doomed_rules'  => ( is => 'ro', lazy => 1, default => sub { ['cpgreylistd'] } );
has '+ports'         => ( is => 'ro', lazy => 1, default => sub { [qw{ /var/run/cpgreylistd.sock }] } );

sub check_sanity {

    # We are always sane cause all of the logic to
    # manage the service (re)starts/stops lives within the daemon itself
    return 1;
}

1;
