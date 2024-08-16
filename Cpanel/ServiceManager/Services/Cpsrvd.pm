package Cpanel::ServiceManager::Services::Cpsrvd;

# cpanel - Cpanel/ServiceManager/Services/Cpsrvd.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;

use Cpanel::Server::PIDFile     ();
use Cpanel::ServiceManager::Hot ();    # PPI USE OK - extends
extends 'Cpanel::ServiceManager::Hot';

use Cpanel::Services::Dormant ();

has '_ipv6_listen'              => ( is => 'ro', lazy => 1, default => sub { -e '/var/cpanel/ipv6_listen'    ? 1 : 0 } );
has '_cpsrvd_started_with_ipv6' => ( is => 'ro', lazy => 1, default => sub { -e '/var/cpanel/cpsrvd_ipv6_ok' ? 1 : 0 } );
has '_ipv6_changed'             => ( is => 'ro', lazy => 1, default => sub { $_[0]->_ipv6_listen != $_[0]->_cpsrvd_started_with_ipv6 } );

has '+is_cpanel_service' => ( is => 'ro', default => 1 );
has '+pidfile'           => ( is => 'ro', default => Cpanel::Server::PIDFile::PATH() );
has '+service_override'  => ( is => 'rw', default => 'cpanel' );

has '+pid_exe'                     => ( is => 'ro', lazy => 1, default => sub { qr{^(?:cpsrvd|cpaneld|webmaild|whostmgrd)|/cpsrvd$|/perl(?:\d+)?$|/libexec/cpsrvd-dormant$} } );
has '+doomed_rules'                => ( is => 'ro', lazy => 1, default => sub { [ 'cpsrvd', 'cpaneld', 'webmaild', 'whostmgrd' ] } );
has '+service_binary'              => ( is => 'ro', lazy => 1, default => sub { $_[0]->dormant_mode_on() ? '/usr/local/cpanel/libexec/cpsrvd-dormant' : '/usr/local/cpanel/cpsrvd' } );
has '+ports'                       => ( is => 'ro', lazy => 1, default => sub { [qw{ 2083 2084 2086 2087 2095 2096 }] } );
has '+graceful_by_default'         => ( is => 'rw', lazy => 1, default => sub { $_[0]->_ipv6_changed ? 0 : 1 } );
has '+is_graceful_restart_enabled' => ( is => 'rw', lazy => 1, default => sub { $_[0]->_ipv6_changed ? 0 : 1 } );

has 'dormant_mode_on' => ( is => 'ro', lazy => 1, default => sub { Cpanel::Services::Dormant->new( 'service' => 'cpsrvd' )->is_enabled() } );

has '+startup_args' => ( is => 'ro', lazy => 1, default => sub { return $_[0]->service_manager()->this_process_was_executed_by_systemd() ? [q{--systemd}] : undef } );

sub start {
    my $self = shift;

    # Case 63039: disable compression due to CRIME attack.
    local $ENV{'OPENSSL_NO_DEFAULT_ZLIB'} = 1;
    delete $ENV{'TMP'};
    delete $ENV{'TEMP'};
    return $self->SUPER::start(@_) ? 1 : 0;
}

1;
