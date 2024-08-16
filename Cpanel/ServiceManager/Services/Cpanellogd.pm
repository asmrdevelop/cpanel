package Cpanel::ServiceManager::Services::Cpanellogd;

# cpanel - Cpanel/ServiceManager/Services/Cpanellogd.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Moo;
use Cpanel::ServiceManager::Base ();
extends 'Cpanel::ServiceManager::Base';

has '+pidfile'        => ( is => 'ro', default => '/var/run/cpanellogd.pid' );
has '+service_binary' => ( is => 'ro', default => '/usr/local/cpanel/cpanellogd' );
has '+suspend_time'   => ( is => 'ro', default => 60 );

has '+doomed_rules'  => ( is => 'ro', lazy => 1, default => sub { ['cpanellogd'] } );
has '+shutdown_args' => ( is => 'ro', lazy => 1, default => sub { [qw{ --stop }] } );

1;
