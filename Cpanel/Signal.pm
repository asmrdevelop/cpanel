package Cpanel::Signal;

# cpanel - Cpanel/Signal.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug ();

# Reload config but do not restar
sub send_hup_cpsrvd {
    return if ( send_hup('cpsrvd') );

    # Previous logic just shuts it down if hup fails but never re-starts it.
    print "Could not send a signal to cpsrvd to restart. Forcing it down with startcpsrvd\n";

    require Cpanel::ServerTasks;
    local $@;
    eval {

        # Schedule in a second.
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, 'startcpsrvd' );
        1;
    };

    if ($@) {
        Cpanel::Debug::log_warn("Failure to schedule task: $@");
        return 0;
    }

    return 1;

}

sub send_hup_dnsadmin {
    return send_hup('dnsadmin');
}

sub send_hup_cpanellogd {
    return send_hup('cpanellogd');
}

sub send_hup_cphulkd {
    return send_hup( 'cPhulkd', '/var/run/cphulkd_processor.pid' );
}

sub send_hup_proftpd {
    return send_hup( 'proftpd', '/var/proftpd.pid' );
}

sub send_hup_tailwatchd {
    return send_hup( 'tailwatchd', '/var/run/tailwatchd.pid' );
}

sub send_usr1_tailwatchd {
    return send_usr1( 'tailwatchd', '/var/run/tailwatchd.pid' );
}

sub send_hup {
    my ( $proc_name, $pidfile ) = @_;
    return _send_signal( $proc_name, $pidfile, 'HUP' );
}

sub send_usr1 {
    my ( $proc_name, $pidfile ) = @_;
    return _send_signal( $proc_name, $pidfile, 'USR1' );
}

sub _send_signal {
    my ( $proc_name, $pidfile, $signal ) = @_;
    return if !$proc_name;
    $pidfile ||= "/var/run/$proc_name.pid";

    if ( open( my $pid_fh, '<', $pidfile ) ) {
        if ( defined read( $pid_fh, my $pid_file_contents, 4096 ) ) {
            close $pid_fh;

            if ( $pid_file_contents =~ m<\A([0-9]+)\s*\z> ) {
                my $pid = $1;

                if ( $pid < 2 ) {
                    Cpanel::Debug::log_warn("$pidfile contained an invalid PID ($pid)");
                }
                else {
                    return 1 if kill( $signal, $1 );
                }
            }
            else {
                Cpanel::Debug::log_warn("$pidfile contains invalid data: “$pid_file_contents”");
            }
        }
        else {
            Cpanel::Debug::log_warn("Failed to read $pidfile: $!");
        }
    }

    require Cpanel::Kill;
    my ( $ok, $procs_killed, $msg ) = Cpanel::Kill::killall( $signal, $proc_name, undef, undef, { 'root' => 1 } );
    return $procs_killed;

}

1;
