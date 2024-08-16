package Cpanel::Backup::Sync;

# cpanel - Cpanel/Backup/Sync.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use File::Basename ();
use Try::Tiny;

use Cpanel::Autodie ('exists');
use Cpanel::Context           ();
use Cpanel::Finally           ();
use Cpanel::Hostname          ();
use Cpanel::Fcntl             ();
use Cpanel::FileUtils::Dir    ();
use Cpanel::FileUtils::Write  ();
use Cpanel::Logd::Constants   ();
use Cpanel::SignalManager     ();
use Cpanel::PsParser          ();
use Cpanel::Wait::Constants   ();
use Cpanel::Sys::Setsid::Fast ();
use Cpanel::LoadFile          ();
use Cpanel::Services          ();

# The names of the pid files used by the old and new backup system
use constant BACKUP_TYPE_OLD => 'backuprunning';
use constant BACKUP_TYPE_NEW => 'new_backuprunning';

# Return codes when setting the backup to be running
use constant SUCCESS            => 0;
use constant OTHER_TYPE_RUNNING => 1;
use constant ERROR              => 2;

our $TIME_TO_WAIT_FOR_STATS = 30;

#
# This will act as an interprocess mutex
#
{

    package Cpanel::Backup::Sync::ProcessMutex;

    use strict;

    sub new {
        my ( $class, $file, $logger ) = @_;

        my $fh;
        if ( !sysopen( $fh, $file, $Cpanel::Fcntl::Constants::O_CREAT ) ) {
            $logger->warn("Failed to sysopen $file: $!");
            return undef;
        }

        my $self = { handle => $fh };
        bless $self, $class;

        flock $fh, $Cpanel::Fcntl::Constants::LOCK_EX or do {
            $logger->warn("Failed to flock($file): $!");
        };

        return $self;
    }

    sub DESTROY {
        my ($self) = @_;

        if ( exists $self->{handle} ) {
            flock $self->{handle}, $Cpanel::Fcntl::Constants::LOCK_UN;
            close $self->{handle};
            delete $self->{handle};
        }
        return;
    }

    1;
}

#
# Handle the case of another instance of the script already running.
#
# If no other backup is running, returns 1.
#
# Otherwise, find the current backup’s log file, inform the user about it,
# then return 0. (An exception is thrown if we fail to find the log file.)
#
sub handle_already_running {
    my ( $id, $logdir, $logger ) = @_;

    my $pid_file = _get_pid_file_path($id);

    # This will return a pid value if the pid
    # file exists, contains a valid pid, and the pid
    # is a running backup process
    my $previous_pid = _validate_pid_file($pid_file);

    # Success, not already running
    return 1 if !$previous_pid;

    $logger->info("A backup process (ID: $previous_pid) is already running.");

    my $logs_ar = Cpanel::FileUtils::Dir::get_directory_nodes($logdir);
    my @logs    = grep( /^\d+\.log$/, sort @$logs_ar );

    if ( $logs[-1] ) {
        $logger->info("Backup log file: $logdir/$logs[-1]");
        $logger->info("To watch the backup, run:\n\t\ttail -f $logdir/$logs[-1]");
    }
    else {
        $logger->info("No previous backup log found!");
    }

    # Not success, should exit
    return 0;
}

#
# Set the backup as running, but not if the other backup type is running
# We need to verify that the other backup type is not running
# and set ours as running in one step inside a critical section
# in case the other script is trying to do the same thing at the same time
#
# Returns an integer value based on the outcome
#
sub set_backup_as_running {
    my ( $id, $other_id, $now, $logger ) = @_;

    # Make this function run in a critical section
    my $lock = Cpanel::Backup::Sync::ProcessMutex->new( '/var/cpanel/.cpanel.backup.sync.lock', $logger );
    return ERROR unless $lock;

    my $pid_file       = _get_pid_file_path($id);
    my $other_pid_file = _get_pid_file_path($other_id);

    if ( _validate_pid_file($other_pid_file) ) {
        $logger->warn("The other backup type is running as evidenced by the existence of:  $other_pid_file");
        return OTHER_TYPE_RUNNING;
    }

    _write_pid_file( $pid_file, $logger );

    # We are successful iff we created our pidfile
    return ERROR unless Cpanel::Autodie::exists($pid_file);

    my $localtime = localtime($now);
    $logger->info("Started at $localtime");

    return SUCCESS;
}

#
# Wait for the other backup type to finish,
# When it does, set our type as having started
# Will stop retrying if the timeout is reached
#
sub set_backup_as_running_after_other_finishes {
    my ( $id, $other_id, $now, $logger, $time_out_seconds ) = @_;

    # Default to 4 hours if no timeout is set
    $time_out_seconds = 4 * 60 * 60 if !defined $time_out_seconds || $time_out_seconds <= 0;

    # Get value of time after which we will stop
    # waiting for the other backup type to stop
    my $max_time = $now + $time_out_seconds;

    my $script_name = File::Basename::basename($0);

    # keep trying to set self as running,
    # Sleep a bit and retry if the other backup type is running
    my $rc = set_backup_as_running( $id, $other_id, $now, $logger );
    while ( ( time() < $max_time ) && ( $rc != SUCCESS ) ) {
        $logger->info("$script_name is waiting for the other backup to complete");
        sleep 60;
        $rc = set_backup_as_running( $id, $other_id, $now, $logger );
    }

    return $rc;
}

#
# Test if cpanellogd is running statistics
#
sub are_stats_running {
    if ( Cpanel::Autodie::exists($Cpanel::Logd::Constants::STATS_PID_FILE) ) {
        my $stats_pid = Cpanel::LoadFile::load($Cpanel::Logd::Constants::STATS_PID_FILE);

        if ( $stats_pid && kill( 0, $stats_pid ) > 0 ) {
            return 1;
        }
    }

    return 0;
}

#
# If stats are running, request to pause cpanellogd and
# wait for it to pause before proceeding
#
sub pause_stats_if_needed {
    my ($logger) = @_;

    my $host        = Cpanel::Hostname::gethostname();
    my $wait_count  = 0;
    my $orig_name   = $0;
    my $script_name = File::Basename::basename($0);

    while ( are_stats_running() ) {
        $logger->info('backups waiting on stats to pause..');
        $0 = "$script_name - Waiting on stats to pause before processing backups";
        if ( !-e '/var/cpanel/backups_need_to_run' ) {

            # create file to alert cpanellogd to pause what it's doing, once cpanellogd says it's done by removing the file (?) cpbackup continues
            if ( open( my $state_fh, '>', '/var/cpanel/backups_need_to_run' ) ) {    # there has to be a better name/place for this.
                print $state_fh "0\n";                                               # set 0 at first, later we read it until it cpanellogd changes it to 1, signalling it has acknowledged this request to pause stats
                close($state_fh);
            }
            else {
                $logger->info("Could not create /var/cpanel/backups_need_to_run : $!");
            }
        }

        my $ready = 0;
        if ( open( my $state_fh, '<', '/var/cpanel/backups_need_to_run' ) ) {
            $ready = <$state_fh>;
            close($state_fh);
        }
        else {
            $logger->info("Could not read from /var/cpanel/backups_need_to_run : $!");
        }

        if ( $ready == 1 ) {

            # stats are paused, continue with backup
            $logger->info("Stats processing appears to have been paused as requested, continuing with backup");
            last;
        }
        else {

            # we need to wait a little longer, stats have been notified to stop but have not responded yet
            $wait_count++;
            sleep($TIME_TO_WAIT_FOR_STATS);
        }

        if ( $wait_count > 960 ) {    # we've been waiting for at least 480 minutes / 8 hours already, something is up..
            if ( -t STDIN ) {
                $logger->info("Backups have been waiting on cpanellogd process to finish for over 8 hours.");
            }

            require Cpanel::Notify;
            Cpanel::Notify::notification_class(
                'class'            => 'Backup::Delayed',
                'application'      => 'cpbackup',
                'status'           => 'waiting on stats',
                'priority'         => 2,
                'interval'         => 60 * 60 * 22,         # One day less two hours in case we start/end a few minutes before we did the day before
                'constructor_args' => {
                    'origin' => 'cpbackup',
                }
            );

            $wait_count = 0;

            # backups are more important than stats and by this point we have made our best effort to honor the setting in WHM to not run
            # them at the same time, but backups must be made.
            $logger->info('Backups continuing despite stats/bandwidth running due to 8 hours of waiting on a single account to finish processing');
            last;
        }
    }

    $0 = $orig_name;
    return;
}

#
# Check if a backup is requesting to pause the stats
#
sub check_for_backups_requesting_pause {

    # check to see if cpbackup is requesting to run, pause what we are doing and let cpbackup know it's ok, then wait until cpbackup is done
    if ( open( my $state_fh, '<', '/var/cpanel/backups_need_to_run' ) ) {
        chomp( my $ready = <$state_fh> );
        close($state_fh);
        main::StatsLog( 0, "dologs() - found $ready in /var/cpanel/backups_need_to_run" );

        if ( $ready == 0 ) {
            if ( open( my $state_fh, '>', '/var/cpanel/backups_need_to_run' ) ) {
                print $state_fh "1\n";
                close($state_fh);

                while (1) {
                    for ( my $time = 0; $time < 60; $time += 2 ) {
                        if ( -e '/var/cpanel/backups_need_to_run' ) {
                            main::StatsLog( 0, "Waiting on backups to continue processing logs." );
                            sleep(120);    # wait 2 minutes and check again
                        }
                        else {
                            return;        # cpbackup has unlinked the file at the end of the run, so we can carry on
                        }
                    }

                    # Check every hour to make sure that cpbackup is still running.
                    if (   !Cpanel::Services::check_service( 'service' => 'cpbackup', 'user' => 'root' )
                        && !Cpanel::Services::check_service( 'service' => 'backup', 'user' => 'root' ) ) {
                        main::StatsLog( 0, "No longer waiting on backups due to dead backup process." );
                        return;
                    }
                }
            }
        }
        else {
            main::StatsLog( 0, "Found value of $ready in /var/cpanel/backups_need_to_run but expected 0" );
        }
    }
    return;
}

#
# Delete any of our files indicating that we are running
#
sub clean_up_pid_files {
    my ($id) = @_;

    my $pid_file = _get_pid_file_path($id);

    unlink $pid_file;
    unlink '/var/cpanel/backups_need_to_run';
    return;
}

sub log_file_path {
    my ( $logdir, $timestamp ) = @_;

    return "$logdir/$timestamp.log";
}

#Redirects to the path that log_file_path() returns.
#
#Returns a Cpanel::SignalManager object and a Cpanel::Finally object;
#these handle deletion of the PID file when the process ends.
#
sub fork_and_redirect_output {
    my ( $id, $logdir, $now, $logger, $complete_cr ) = @_;

    Cpanel::Context::must_be_list();

    my $script_name = File::Basename::basename($0);

    my $log_file = log_file_path( $logdir, $now );

    # Get set up to receive a signal when the child process is started and operational
    my $parent_pid    = $$;
    my $child_started = 0;
    local $SIG{'USR2'} = sub { $child_started = 1 };

    my $child_pid = fork();
    if ( !defined $child_pid ) {
        $logger->die("Unable to fork:  $!");
    }

    # Handle the case for the parent process, wait for the child to fully start before exiting
    if ($child_pid) {

        if ( -t STDIN ) {
            $logger->info("The backup is now running in the background in process $child_pid.");
            $logger->info("The backup process’s log file is “$log_file”.");
        }

        my $start_time     = time();
        my $waitpid_result = waitpid( $child_pid, $Cpanel::Wait::Constants::WNOHANG );

        # wait up to a minute for us to have received the signal from the child process
        while ( !$child_started and time() - $start_time < 60 and !$waitpid_result ) {
            sleep 1;
            $waitpid_result = waitpid( $child_pid, $Cpanel::Wait::Constants::WNOHANG );
        }

        # If we haven't received the signal or the child process has exited, we failed
        if ( !$child_started or $waitpid_result ) {
            $logger->die('Unable to start child process');
        }

        exit 0;
    }

    # Put child process in its own process group and detach from any tty's
    Cpanel::Sys::Setsid::Fast::fast_setsid();

    # Need to re-write the PID file since the PID changed as a result forking
    my $pid_file = _get_pid_file_path($id);
    _write_pid_file( $pid_file, $logger );

    my $original_pid = $$;

    # Set to delete the pid file if we are killed/die
    my $finish_cr = sub {
        my ($signal) = @_;
        if ( $$ == $original_pid ) {
            if ($complete_cr) {
                eval { $complete_cr->($signal); };
            }

            unlink $pid_file or do {
                warn "Failed to unlink($pid_file): $!" if !$!{'ENOENT'};
            };
        }
    };

    # Make sure that if this thread is killed that pid file will be cleaned up
    my ( $sig_manager, $at_end ) = _set_handler($finish_cr);

    # Signal the parent process that we are alive and it can exit
    kill 'USR2' => $parent_pid;

    my $ok = sysopen(
        my $bcklog_fh,
        $log_file,
        Cpanel::Fcntl::or_flags(qw( O_WRONLY O_TRUNC O_CREAT O_APPEND )),
        0600
    );
    $logger->die("Could not open backup log “$log_file”: $!") if !$ok;

    open( STDOUT, '>>&', $bcklog_fh )  || $logger->info("Could not redirect STDOUT: $!");
    open( STDERR, '>>&', $bcklog_fh )  || $logger->info("Could not redirect STDERR: $!");
    open( STDIN,  '<',   '/dev/null' ) || $logger->info("Could not redirect STDIN: $!");

    # Do not close fds here as this will cause an fd leak when run from crontab
    return ( $sig_manager, $at_end );
}

#
# Make sure that the pid file will be cleaned up if the current thread is killed
# Other threads can be spawned without them deleting the pid file
#
sub _set_handler {
    my ($finish_cr) = @_;

    my $sigman = Cpanel::SignalManager->new();

    for my $sig ( $sigman->FATAL_SIGNALS() ) {
        $sigman->push( signal => $sig, handler => $finish_cr );

        # We enable resend so the process still dies
        # with the signal that was sent in order
        # to make sure we report the correct signal to
        # whoever is watching.
        $sigman->enable_signal_resend( signal => $sig );
    }

    return ( $sigman, Cpanel::Finally->new($finish_cr) );
}

#
# Returns true if either type of backup is running
#
sub are_backups_running {
    return ( ( _validate_pid_file( _get_pid_file_path(BACKUP_TYPE_NEW) ) ) || ( _validate_pid_file( _get_pid_file_path(BACKUP_TYPE_OLD) ) ) );
}

#----------------------------------------------------------------------
#
# "Private" functions
#

#
# Return the pid if the pid file exists and contains the pid
# of a valid process; otherwise, returns 0.
#
# Throws a suitable exception on error.
#
sub _validate_pid_file {
    my ($file_name) = @_;

    # If it doesn't exist, then that would be a "no"
    return 0 unless Cpanel::Autodie::exists($file_name);

    # Read the pid out of the file
    my $pid = _read_pid_file($file_name);

    # See that the pid belongs to a valid process
    return 0 unless ( $pid && ( kill( 0, $pid ) > 0 ) );

    # Make sure the process is a backup process
    my $cmd = _get_pid_command($pid);

    # It must contain "backup" if it is a backup process
    return ( $cmd =~ /backup/ ) ? $pid : 0;
}

#
# Get the command associated with a process id
#
sub _get_pid_command {
    my ($pid) = @_;

    my $pidinfo = Cpanel::PsParser::get_pid_info($pid);
    if ($pidinfo) {
        return $pidinfo->{'command'};
    }
    return;
}

#
# From the ID of the backup type, generate the
# full path for our pid file
#
sub _get_pid_file_path {
    my ($id) = @_;

    return "/var/cpanel/" . $id;
}

sub _read_pid_file {
    my ($pid_file) = @_;

    chomp( my $pid = Cpanel::LoadFile::load($pid_file) );

    return int( abs($pid) );
}

#
# Write out the pid file
#
sub _write_pid_file {
    my ( $pid_file, $logger ) = @_;

    try {
        Cpanel::FileUtils::Write::overwrite( $pid_file, $$ );
    }
    catch {
        my $script_name = File::Basename::basename($0);
        $logger->die( "[$script_name] Unable to open $pid_file: " . $_->to_string() );
    };

    return;
}
