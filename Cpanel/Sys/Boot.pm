package Cpanel::Sys::Boot;

# cpanel - Cpanel/Sys/Boot.pm                       Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

use cPstrict;

use Cpanel::OS ();

our $VERSION = '1.0';

sub is_booting {

    if ( Cpanel::OS::is_systemd() ) {    # maybe use a different question?
        if ( defined( my $systemd_is_operational = systemd_state_is_operational() ) ) {    # Fall through if not defined.
            return ( $systemd_is_operational ? 0 : 1 );
        }
        return 1 if 'active' ne _run_systemctl(qw{ is-active multi-user.target });         # Fall back to original but less accurate test
    }
    else {
        chomp( my $runlevel = _run_runlevel() );
        return 1 if !$runlevel;
        return 1 if $runlevel !~ m/\b([0-9])$/;
        return 1 if $1 < 3;
    }

    return 0;
}

# helpers for test coverage
sub _run_runlevel() {
    chomp( my $runlevel = qx{/sbin/runlevel} );    ## no critic qw(ProhibitQxAndBackticks)
    return $runlevel;
}

sub _run_systemctl (@args) {

    # when running under systemd there's a problem with the exit code of systemctl so #
    # we'll use the string value instead #
    my $cmd = join ' ', '/usr/bin/systemctl', @args;
    chomp( my $res = qx/$cmd/ );    ## no critic qw(ProhibitQxAndBackticks)

    return $res || 'unknown';
}

sub systemd_state_is_operational() {

    # This is similar to 'systemctl is-system-running' and checks the same SystemState property but that command is not available until systemd >= 215 (CentOS >= 7.2).

    my $res = _run_systemctl(qw{ show --property=SystemState });

    # $res can be one of the following:
    #  ''                          # 'systemctl' returned an empty response, and that happens for exactly the same reason that 'systemctl is-system-running' can return an 'unknown' response
    #  'unknown'                   # Can be returned by _run_systemctl
    #  'SystemState=initializing'
    #  'SystemState=starting'
    #  'SystemState=running'       # systemd transitions to this state OR degraded after the boot job queue is empty. "systemd: Startup finished [...]" is printed in /var/log/messages
    #  'SystemState=degraded'      # Same operational state as 'running' but one or more units have failed.  It can transition between running and degraded at ANY TIME after boot!
    #  'SystemState=maintenance'
    #  'SystemState=stopping'

    return undef unless length $res;      # Allows fall back
    return undef if $res eq 'unknown';    # Allows fall back

    return 1 if $res eq 'SystemState=running';
    return 1 if $res eq 'SystemState=degraded';    # This Is Fine (insert appropriate meme) for our purposes

    return 0;
}

1;
