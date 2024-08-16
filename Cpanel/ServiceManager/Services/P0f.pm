package Cpanel::ServiceManager::Services::P0f;

# cpanel - Cpanel/ServiceManager/Services/P0f.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Base ();
use Cpanel::Net::P0f::Config     ();

extends 'Cpanel::ServiceManager::Base';

has '+is_cpanel_service' => ( is => 'ro', default => 1 );
has '+service_package'   => ( is => 'ro', default => 'p0f' );
has '+service_binary'    => ( is => 'ro', default => '/usr/local/cpanel/3rdparty/sbin/p0f' );
has '+processowner'      => ( is => 'ro', default => 'cpanelconnecttrack' );

has '+doomed_rules' => ( is => 'ro', lazy => 1, default => sub { ['p0f'] } );
has '+startup_args' => ( is => 'ro', lazy => 1, default => sub { [ '-i', 'any', '-u', 'cpanelconnecttrack', '-d', '-s', $Cpanel::Net::P0f::Config::SOCKET_PATH, 'less 400 and not dst port 80 and not dst port 443 and tcp[13] & 8==0' ] } );

1;
