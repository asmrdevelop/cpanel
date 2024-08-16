package Cpanel::TailWatch::Utils::Stop;

# cpanel - Cpanel/TailWatch/Utils/Stop.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Kill::Single ();

sub Cpanel::TailWatch::stop {
    my ( $self, $quiet ) = @_;
    $quiet ||= 0;
    my $curpid = $self->get_pid_from_pidfile();

    if ($curpid) {

        # This kill allows tailwatch to perform cleanup
        kill( 'TERM', $curpid );

        my $running = 1;

        # Give tailwatch some time to clean itself up
        for ( my $cnt = 0; $cnt < 30; $cnt++ ) {
            if ( kill 'ZERO', $curpid ) {
                sleep 1;
            }
            else {
                $running = 0;
                last;
            }
        }

        if ($running) {

            # If the process hasn't exited yet, try the more robust Safekill
            if ( Cpanel::Kill::Single::safekill_single_pid($curpid) ) {
                $self->log("[STOP ??] $curpid") or die "Could not initiate log $self->{'log_file'}: $!";
                $self->log_and_say("Could not stop current process '$curpid'\n");
                return;
            }
        }
        $self->log("[STOP Ok] $curpid") or die "Could not initiate log $self->{'log_file'}: $!";
        $self->log_and_say("Current process '$curpid' stopped\n");
        unlink $self->{'pid_file'};
    }
    else {
        print $self->_add_stamp("No PID in $self->{'pid_file'}\n") if !$quiet;
    }
    return 1;
}

1;
