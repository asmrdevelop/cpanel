package Cpanel::Daemonizer;

# cpanel - Cpanel/Daemonizer.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::LoggerAdapter ();
use Unix::PID             ();
use Cpanel::Sys::Setsid   ();

#
# Constructor
# Params:
#   identifier - Identifer, short name for the daemon, used to name the PID file
#   name - Display name, used in logs
#   logger - Cpanel::Logger object (Optional)
#
sub new {
    my ( $class, %OPTS ) = @_;

    # enforce required params
    if ( !defined $OPTS{'identifier'} ) {
        return ( 0, 'parameter "identifier" is required' );
    }
    if ( !defined $OPTS{'name'} ) {
        return ( 0, 'parameter "name" is required' );
    }

    # If the logger wasn't supplied, then create one.
    my $logger = defined $OPTS{'logger'} ? $OPTS{'logger'} : Cpanel::LoggerAdapter->new( { alternate_logfile => "/usr/local/cpanel/logs/$OPTS{'identifier'}.log" } );

    my $self = bless {
        'identifier' => $OPTS{'identifier'},
        'name'       => $OPTS{'name'},
        'logger'     => $logger,
        'debug'      => $ENV{'CP_DAEMONIZER_DEBUG'},
        'verbose'    => $OPTS{'verbose'} || $ENV{'CP_DAEMONIZER_DEBUG'},
        'pidfile'    => "/var/run/$OPTS{'identifier'}.pid",
        'pidobj'     => Unix::PID->new( { use_open3 => 0 } ),
        'is_running' => 0,
    }, $class;

    return ( 1, $self );
}

#
# Run the process in the background (unless the debug ENV variable is set)
# Checks the PID file so that only one thread per identifier is allowed
#
sub start {
    my ($self) = @_;

    $self->{'is_running'} = 1;

    # Set up our handlers
    $self->_setup_handlers();

    # Don't fork if we are already running
    if ( $self->_daemon_already_running() ) {
        my $msg = "$self->{'name'} Daemon already running, exiting.";
        $self->{'logger'}->throw($msg);
    }

    # Do the actual forking
    $self->_fork_daemon();

    # In order to remove the race condition, we need to test again after the fork.
    # This use of Unix::PID removes the race condition when creating the pidfile.
    if ( !$self->{'pidobj'}->pid_file_no_unlink( $self->{'pidfile'} ) ) {
        my $msg = "$self->{'name'} Daemon already running, exiting.";
        $self->{'logger'}->throw($msg);
    }

    # Finish and cleanup
    $self->_finish_starting();
    return;
}

#
# Run the process in the background (unless the debug ENV variable is set)
# Allows multiple threads per identifier
#
sub start_non_exclusive {
    my ($self) = @_;

    $self->{'is_running'} = 1;

    # Set up our handlers
    $self->_setup_handlers();

    # Do the actual forking
    $self->_fork_daemon();

    # Finish and cleanup
    $self->_finish_starting();
    return;
}

#
# Clean up the PID file and exits
#
sub stop {
    my ($self) = @_;

    my $name    = $self->{'name'};
    my $logger  = $self->{'logger'};
    my $pidfile = $self->{'pidfile'};
    my $pidobj  = $self->{'pidobj'};

    # All done, log message and cleanup PID file
    $logger->info("$name Daemon is being stopped.");
    unlink $pidfile if $$ == $pidobj->get_pid_from_pidfile($pidfile) || !$pidobj->is_pidfile_running($pidfile);

    # we probably want to exit there ?
    return;
}

#
# Halts all occurrences of this daemon
# Wait time param determines the the time delay between graceful and forceful shutdown
#
sub halt_all_instances {
    my ( $self, $wait_time ) = @_;

    my $name = $self->{'name'};
    $wait_time = $wait_time > 0 ? $wait_time : 1;

    # is anyone running ?
    my @pids = $self->get_other_pids();

    # If none running, nothing to do, return success
    if ( scalar @pids == 0 ) {
        print "No $name Daemon detected.\n" if $self->{'verbose'};
        return 1;
    }

    # Ask them all to die nicely
    kill 1 => $_ foreach @pids;
    print "Graceful shutdown of $name Daemon requested.\n" if $self->{'verbose'};

    # Wait for them to die
    foreach ( 1 .. $wait_time ) {
        @pids = $self->get_other_pids();

        # We're done if they are all dead
        last unless scalar @pids;

        # Wait a second & check again
        sleep 1;
    }

    # See if we're done, if not, then kill harder
    if ( scalar @pids == 0 ) {
        print "Shutdown complete\n" if $self->{'verbose'};
        return 1;
    }
    else {
        print "Shutdown not complete. Taking more serious measures.\n";
    }

    # Try again to kill them all, different signal
    kill 15 => $_ foreach @pids;

    # Wait a little bit & see if any left
    sleep 1;
    @pids = $self->get_other_pids();

    # Totally get medieval on any survivors
    kill 9 => $_ foreach @pids;

    # Wait for them to die, if that didn't get them then nothing will
    foreach ( 1 .. $wait_time ) {

        # We're done if they are all dead
        last unless ( scalar @pids );

        # Wait a second & check again
        sleep 1;
        @pids = $self->get_other_pids();
    }

    # If any are still left, shrug & return an error
    if ( scalar @pids ) {
        print "Unable to kill all $name Daemons\n";
        return 0;
    }

    # Success
    return 1;
}

#
# Returns a boolean determining whether the process should be running
#
sub is_running {
    my ($self) = @_;

    return $self->{'is_running'};
}

#
# Set the status message for the thread
# Having the status message start with "$id - " is
# what allows get_pidof() to id the task
#
sub set_status_msg {
    my ( $self, $msg ) = @_;

    $0 = "$self->{'identifier'} - $msg";
    $self->{'logger'}->info("$0");
    return;
}

#
# Returns an array of the PIDs of the daemon for the given identifier
# Static function
#
sub get_running_pids {
    my ( $identifier, $pidobj ) = @_;

    # pidobj is optional, if none is passed in, just
    # allocate one
    $pidobj = Unix::PID->new( { use_open3 => 0 } ) unless defined $pidobj;

    # We rename all of the queue instances to contain the ' - '
    # This prevents us from killing the start/restart scripts.
    return $pidobj->get_pidof("$identifier - ");
}

#
# Gets an array of pid's for this objects' daemon
#
sub get_other_pids {
    my ($self) = @_;

    # current pid is never included in that list
    my @pids = get_running_pids( $self->{'identifier'}, $self->{'pidobj'} );
    return @pids;
}

#
# Private functions
#

#
# Called by the handler that we set
#
sub _reaper {
    my ($logger) = @_;

    my $thedead;
    while ( ( $thedead = waitpid( -1, 1 ) ) > 0 ) {
        if ( $? & 127 ) {
            $logger->info( "Child [$thedead]: exited with signal " . ( $? & 127 ) . "\n" );
        }
    }
    $SIG{'CHLD'} = sub { _reaper($logger); };
    return $SIG{'CHLD'};
}

#
# Examines the PID file to see if this daemon is already running
#
sub _daemon_already_running {
    my ($self) = @_;

    my $pidfile = $self->{'pidfile'};
    my $pidobj  = $self->{'pidobj'};

    return unless -e $pidfile;
    my $pid = $pidobj->get_pid_from_pidfile($pidfile);
    return 0 unless $pid;

    # if we can use kill to check the pid, it is best choice.
    my $fileuid = ( stat($pidfile) )[4];
    if ( $> == 0 || $> == $fileuid ) {

        # kill can return 0 on permissions problem, not just from missing process
        # Check the permissions. Despite the 'Errno' inclusion of %!, removing
        # it does not reduce the memory, it actually increases memory usage by
        # 72K in testing.
        return 0 unless kill( 0, $pid ) or $!{EPERM};
    }

    # If the proc filesystem is available, it's a good test.
    return ( -r "/proc/$pid" && $pid ) if -e "/proc/$$" && -r "/proc/$$";

    # get a list of pids for queueprocd processes from ps
    #   there should only be at most two, ours and the real one, but it doesn't
    #   hurt to try to deal with the possibility that I blew it.

    # Is the expected pid found in the ps output.
    # note that the current pid is never included in the output
    return ( scalar grep { $pid == $_ } $self->get_other_pids(), $$ ) ? 1 : 0;
}

#
# Setup the handlers for our thread
#
sub _setup_handlers {
    my ($self) = @_;

    $SIG{'HUP'} = sub {
        $self->{'logger'}->info("Graceful shutdown due to SIGHUP\n");
        $self->{'is_running'} = 0;
        print "Graceful shutdown due to SIGHUP $$\n" if $self->{verbose};
        exit;    # do the graceful shutdown...
    };
    $SIG{'CHLD'} = sub { _reaper( $self->{'logger'} ); };
    return $SIG{'CHLD'};
}

#
# Fork the daemon as long as we are not in debug mode
#
sub _fork_daemon {
    my ($self) = @_;

    if ( $self->{'debug'} ) {
        print "Debug option set, not really forking\n";
        return;
    }

    # run in the background unless we are trying to debug/unit-test
    print "==> $self->{'name'} Daemon starting\n" if $self->{'verbose'};

    # We need to set a status message so Unix::PID->get_pidof will recognize
    # this process as starting in order to avoid a race condition
    # where multiple copies are started
    $self->set_status_msg('parent starting');

    my $pid = Cpanel::Sys::Setsid::full_daemonize();

    $self->set_status_msg('child starting');

    # we are the child since full_daemonize will exit
    return;
}

#
# Perform final tasks for starting the daemon
#
sub _finish_starting {
    my ($self) = @_;

    unless ( $self->{'verbose'} ) {
        open STDERR, '>', '/dev/null' or die "Unable to redirect stderr.\n";
        open STDOUT, '>', '/dev/null' or die "Unable to redirect stdout.\n";
    }

    $self->{'logger'}->info("$self->{'name'} Daemon started.");

    # We need to set a status message so Unix::PID->get_pidof will recognize
    # this daemon (It will put the identifier in the status)
    $self->set_status_msg('started');
    return;
}

1;
