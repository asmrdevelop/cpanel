package Cpanel::ServiceManager::Services::Munin;

# cpanel - Cpanel/ServiceManager/Services/Munin.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Moo;
use Cpanel::ServiceManager::Base ();
use Cpanel::Binaries             ();
extends 'Cpanel::ServiceManager::Base';

has '+service_override' => ( is => 'ro', default => 'munin-node' );
has '+service_binary'   => ( is => 'ro', lazy    => 1, default => sub { Cpanel::Binaries::path('munin-node') } );
has '+service_package'  => ( is => 'ro', lazy    => 1, default => sub { 'cpanel-perl-' . Cpanel::Binaries::PERL_MAJOR . '-munin' } );

1;
