package Cpanel::ServiceManager::Services::Dnsadmin;

# cpanel - Cpanel/ServiceManager/Services/Dnsadmin.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Hot ();    # PPI USE OK - extends
extends 'Cpanel::ServiceManager::Hot';

has '+is_cpanel_service' => ( is => 'ro', default => 1 );
has '+pidfile'           => ( is => 'ro', default => '/var/run/dnsadmin.pid' );

# this is a wrapper to start whostmgr/bin/dnsadmin or libexec-dnsadmin-dormant
has '+service_binary'   => ( is => 'rw', default => '/usr/local/cpanel/libexec/dnsadmin-startup' );
has '+suspend_time'     => ( is => 'ro', default => 60 );
has '+restart_attempts' => ( is => 'ro', default => 2 );

has '+pid_exe'      => ( is => 'ro', lazy => 1, default => sub { qr{^(/usr/local/cpanel/3rdparty/perl/[0-9]+/bin/perl|dnsadmin - server)|/dnsadmin$|/libexec/dnsadmin-dormant$} } );
has '+startup_args' => ( is => 'ro', lazy => 1, default => sub { [ qw{ --start }, $_[0]->service_manager()->this_process_was_executed_by_systemd() ? q{--systemd} : () ] } );

sub restart_attempt {
    my ( $self, $retry_attempt ) = @_;

    # this is a protection
    # when failing to start dnsadmin with dnsadmin-startup, switch to the regular binary
    if ( $retry_attempt == 1 ) {
        my $main_bin = q{/usr/local/cpanel/whostmgr/bin/dnsadmin};
        $self->logger()->info( q{The service '} . $self->service() . qq{' failed to restart. Trying '$main_bin'.} );
        $self->service_binary($main_bin);
    }

    return 1;
}

1;
