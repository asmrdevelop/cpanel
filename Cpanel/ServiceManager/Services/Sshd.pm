package Cpanel::ServiceManager::Services::Sshd;

# cpanel - Cpanel/ServiceManager/Services/Sshd.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Base ();
use Cpanel::RestartSrv::Systemd  ();
use Cpanel::Kill                 ();

extends 'Cpanel::ServiceManager::Base';

has '+pidfile'          => ( is => 'ro', default => '/var/run/sshd.pid' );
has '+restart_attempts' => ( is => 'ro', default => 3 );

has '+doomed_rules' => ( is => 'rw', lazy => 1, builder => 1 );

sub restart_attempt {
    my ( $self, $p_attempt ) = @_;

    # Kill existing sshd processes off incase any are holding onto the port, preventing a restart.
    if ( $p_attempt == 2 ) {
        $self->info("Killing off existing sshd processes");
        Cpanel::Kill::killall( 'TERM', 'sshd' );
        return 1;
    }

    return 0;
}

sub _build_doomed_rules {

    return if Cpanel::RestartSrv::Systemd::has_service_via_systemd('sshd');

    # legacy behavior: when not run from a remote client, ensure sshd goes down when restart #
    # NOTE: systemd manages processes and does not need this logic #
    return if length $ENV{'SSH_TTY'} || length $ENV{'SSH_CLIENT'};

    return ['/usr/sbin/sshd'];
}

sub command_line_regex {
    ## on non-systemd systems, restartsrv uses the 'process table scan' method,
    ##   and erroneously picks up active SSH sessions
    if ( !Cpanel::RestartSrv::Systemd::has_service_via_systemd('sshd') ) {
        return '/usr/sbin/sshd';
    }
    return;
}

1;
