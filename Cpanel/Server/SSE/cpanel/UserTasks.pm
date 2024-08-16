package Cpanel::Server::SSE::cpanel::UserTasks;

# cpanel - Cpanel/Server/SSE/cpanel/UserTasks.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf8

=head1 NAME

Cpanel::Server::SSE::cpanel::UserTasks - SSE monitor for user task queue

=head1 SYNOPSIS

    #See parent class for arguments
    my $sse_tasks = Cpanel::Server::SSE::cpanel::UserTasks->new( ... );

    $sse_tasks->run();

=cut

use parent qw( Cpanel::Server::SSE::cpanel );

use Cpanel::Exception ();
use Cpanel::PwCache   ();
use Cpanel::Time::ISO ();
use Cpanel::UserTasks ();

use Cpanel::UserTasksCore::Task                               ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event             ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::Failure    ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::Processing ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::LogUpdate  ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::LogQuit    ();
use Cpanel::Server::SSE::cpanel::UserTasks::Event::Success    ();

use constant {
    _TIMEOUT => 3600,      # 1 hour in seconds
    _SLEEP   => 200000,    # 0.2 second in microseconds
    DEBUG    => 0,         # enable for debugging
};

sub _init ($self) {

    $self->{timeout}    = _TIMEOUT();
    $self->{start_time} = time();

    $self->_setup_output() if DEBUG;

    # order matters, init task set the task id
    # then the log can consume that log id to figure out the best log to use
    $self->_init_task();
    $self->_init_log();

    return;
}

sub _setup_output ($self) {

    open( $self->{_log_fh}, '>>', '/tmp/sse.test.log' ) or return;

    my $fno = fileno $self->{_log_fh} or return;
    open( *STDOUT, '>>&=' . $fno ) or die "open(STDOUT) failed: $!";    ##no critic qw(ProhibitTwoArgOpen)
    open( *STDERR, '>>&=' . $fno ) or die "open(STDERR) failed: $!";    ##no critic qw(ProhibitTwoArgOpen)

    return;
}

=head2 I<OBJ>->_run(...)

Does the main work of this module. It runs an infinite loop until the specified task no
longer exists in the user task queue.

=cut

sub _run ($self) {

    my $task_id  = $self->{task_id};
    my $log_file = $self->{log_file};

    alarm( $self->{timeout} );

    if ( !defined $log_file || !-e $log_file ) {
        no warnings 'once';

        # do not log the access twice...
        local *cpanel::cpsrvd::logaccess = sub { };
        die Cpanel::Exception::create( 'cpsrvd::BadRequest', 'Unable to find a log file.' );
    }

    open( my $fh, '<', $log_file ) or return;

    for ( ;; ) {    # forever or until done event is seen or timeout
        my $log_raw = '';
        while ( my $line = <$fh> ) {
            chomp($line);
            unless ($task_id) {

                # If we are watching the task queue log instead of task log,
                # we do NOT want to go too far back in the log, so if a task
                # takes longer than the time out, it is not going to work
                my $time_stamp;
                if ( $line =~ m/^(\S+Z):/ ) {
                    $time_stamp = $1;
                    $time_stamp = Cpanel::Time::ISO::iso2unix($time_stamp);
                }
                next unless $time_stamp && $time_stamp > $self->{start_time} - _TIMEOUT();
            }

            $log_raw .= $line . "\n";
        }

        if ( length $log_raw ) {
            if ( my $time2quit = $self->_process_log($log_raw) ) {
                $self->send_logquit();
                close $fh;
                return;
            }
        }

        return if $self->_check_if_task_is_done();

        $self->_send_sse_heartbeat();    # Just sending one every .2 second while waiting for new entries.

        Time::HiRes::usleep( _SLEEP() ); # Checking for new entries every .2 seconds.
        seek( $fh, 0, 1 );               # Reset the EOF marker: seek(fh, offset from last param, current position)
    }

    return;
}

sub _check_if_task_is_done ($self) {
    return unless my $task_id = $self->{task_id};

    return if $self->_is_task_alive($task_id);

    $self->{'current_task'} = $task_id;
    $self->send_task_complete();

    return 1;
}

use constant _ACCEPTED_FEATURES => ('any');

sub _init_task ($self) {

    $self->_init_task_id();

    return unless $self->{'task_id'};

    my $task = eval { Cpanel::UserTasks->new()->get( $self->{'task_id'} ) };
    return unless ref $task;

    # setup the log_file from the task
    if ( ref $task->{'args'} && length $task->{'args'}->{'log_file'} ) {

        # otherwise fallback to the queue log
        $self->{'log_file'} = $task->{'args'}->{'log_file'};

        if ( $self->{'log_file'} && $self->{'log_file'} !~ m{^/} ) {
            eval { $self->_get_log_file_path( $self->{'log_file'} ); };
        }

    }

    # the task provides its own sse_processor for the log
    if ( my $subsystem = $task->{'subsystem'} ) {
        if ( my $module = Cpanel::UserTasksCore::Task::load_module($subsystem) ) {
            $self->{'_custom_processor'} = $module->can('sse_process_log');
        }
    }

    $self->{'_custom_processor'} //= \&send_task_log_event;

    return;
}

sub _init_task_id ($self) {

    # init the task_id from args
    return if defined $self->{task_id};
    return unless ref $self->{_args};

    if ( my $id = $self->{_args}->[0] ) {
        $id =~ s{_}{/}g;
        $self->{'task_id'} = $id;
    }

    return;
}

sub _init_log ($self) {

    # fallback to the default log_file when not set
    $self->{'log_file'} //= _get_homedir() . '/.cpanel/logs/user_task_runner.log';
    return;
}

sub _process_log ( $self, $log_raw ) {

    if ( my $processor = $self->{'_custom_processor'} ) {
        return $processor->( $self, $log_raw );
    }

    return $self->_process_queue_log($log_raw);
}

=head2 I<OBJ>->_process_queue_log(...)

Goes through lines from log file and sends appropriate events. Returns undef or 1
to indicate if it is time for the log watcher to quit.

=cut

sub _process_queue_log ( $self, $log_raw ) {

    my $last_event_id = $self->_get_last_event_id();

    my $use_task_runner_log = $self->{'log_file'} =~ m{\Q/user_task_runner.log\E$} ? 1 : 0;

    my @logs = split( /\n/, $log_raw );

    my $task_id = $self->{task_id};

    my $counter      = 0;
    my $time_to_quit = 0;
    foreach my $line (@logs) {
        chomp($line);
        $counter++;

        # end of logs and queue empty, good time to quit
        if ( $counter == $#logs + 1 && $line =~ m/Queue empty/ ) {
            $time_to_quit = 1;
        }

        my $time_stamp;
        if ( $line =~ m/^(\S+Z):/ ) {
            $time_stamp = $1;
            $time_stamp = Cpanel::Time::ISO::iso2unix($time_stamp);
        }

        next unless $time_stamp;

        if ( $line =~ m/\bProcessing\s+([^.]+)/ ) {
            my $next = $1;

            # enforce a valid task id
            $next = $1 if $next =~ m{Task ID (\w+/\w+)};

            my $event;
            if ( $self->{'current_task'} ) {
                $self->send_task_complete($time_stamp);
            }
            if ( !$task_id || !$use_task_runner_log || $task_id eq $next ) {
                $self->{'current_task'} = $next;
                $self->send_task_processing($time_stamp);
            }
        }
        elsif ( $line =~ m/\bQueue empty/ ) {
            if ( !$use_task_runner_log || $self->{'current_task'} ) {
                $self->send_task_complete($time_stamp);
                $self->{'current_task'} = undef;
            }
        }
        elsif ( $line =~ m/\bFAILURE:/ ) {
            if ( !$use_task_runner_log || $self->{'current_task'} ) {
                $self->send_task_failed($time_stamp);
            }
        }

    }

    return $time_to_quit;
}

=head2 I<OBJ>->send_task_log_event( $data )

This is parsing the log and sending 'log_update' or 'task_failed' to the listener.
This helper be consumed by any UserTask when providing their own custom parser.

Note that $data can be a string or a hashref.

=cut

sub send_task_log_event ( $self, $log_raw ) {

    return unless length $log_raw;

    # do not send twice the same event
    return if length $self->{_last_log_raw_sent} && $self->{_last_log_raw_sent} eq $log_raw;

    my $last_event_id = $self->_get_last_event_id();
    my $event         = $self->_create_log_event($log_raw);

    # do not spam the client with messages
    return if defined $last_event_id && $event->{id} <= $last_event_id;

    $self->send($event);    # unless defined $last_event_id && $event->{id} <= $last_event_id;
    $self->{_last_log_raw_sent} = $log_raw unless ref $log_raw;

    return;
}

=head2 I<OBJ>->send_task_complete( $timestamp=undef )

This is sending a 'task_complete' event to the listener.

This helper be consumed by any UserTask when providing their own custom parser.

=cut

sub send_task_complete ( $self, $id = undef ) {

    my $task = Cpanel::Server::SSE::cpanel::UserTasks::Event::Success->new(
        id      => $id,
        task_id => $self->{'current_task'}
    );

    return $self->send($task);

}

=head2 I<OBJ>->send_task_processing( $timestamp=undef )

This is sending a 'task_processing' event to the listener.

This helper be consumed by any UserTask when providing their own custom parser.

=cut

sub send_task_processing ( $self, $id = undef ) {

    my $task = Cpanel::Server::SSE::cpanel::UserTasks::Event::Processing->new(
        id      => $id,
        task_id => $self->{'current_task'}
    );

    return $self->send($task);
}

=head2 I<OBJ>->send_task_failed( $timestamp=undef )

This is sending a 'task_failed' event to the listener.

This helper be consumed by any UserTask when providing their own custom parser.

=cut

sub send_task_failed ( $self, $id = undef ) {

    my $task = Cpanel::Server::SSE::cpanel::UserTasks::Event::Failure->new(
        id      => $id,
        task_id => $self->{'current_task'}
    );

    return $self->send($task);
}

=head2 I<OBJ>->_create_log_event(...)

Returns a hashref that represents the event when a log is being updated.

=cut

sub _create_log_event ( $self, $data ) {

    if ( !ref $data ) {
        my @lines = split /\n/, $data;

        if ( grep /Task completed with exit code\s+[^0]+|^fatal:|Build completed with exit code\s+[^0]+/, @lines ) {
            return Cpanel::Server::SSE::cpanel::UserTasks::Event::Failure->new(    #
                data      => $data,                                                #
                'task_id' => $self->{'task_id'},                                   #
            );
        }
    }

    return Cpanel::Server::SSE::cpanel::UserTasks::Event::LogUpdate->new(    #
        data      => $data,                                                  #
        'task_id' => $self->{'task_id'},                                     #
    );
}

=head2 I<OBJ>->send_logquit(...)

Returns a hashref that represents an event signaling the log watcher
is quitting.

=cut

sub send_logquit ($self) {

    my $task = Cpanel::Server::SSE::cpanel::UserTasks::Event::LogQuit->new();
    return $self->send($task);
}

=head2 I<OBJ>->_get_log_file_path(...)

Finds the log file under ~/.cpanel/logs. Dies if the log file does
not exist.

=cut

sub _get_log_file_path ( $self, $log_file ) {

    $log_file =~ s{^\.\.+}{};

    my $log_dir = _get_homedir();
    $log_dir .= '/.cpanel/logs';
    $log_file = $log_dir . '/' . $log_file;
    if ( !-e $log_file ) {
        die Cpanel::Exception::create( 'cpsrvd::BadRequest', "The requested log file “[_1]” could not be found.", [$log_file] );
    }
    $self->{'log_file'} = $log_file;

    return;
}

sub _get_homedir {
    return $Cpanel::homedir || Cpanel::PwCache::gethomedir();
}

=head2 I<OBJ>->_is_task_alive(...)

Returns 1 or 0 indicating if a specified task id still exists
in the user task queue.

=cut

sub _is_task_alive ( $self, $task_id ) {

    my $ut       = Cpanel::UserTasks->new();
    my $is_alive = eval { $ut->get($task_id); 1 } ? 1 : 0;

    warn("Failed to load UserTasks '$task_id' $@\n") if $@;

    return $is_alive;
}

=head2 I<OBJ>->send(...)

A wrapper function over _send_sse_message to send out an
event.

=cut

sub send ( $self, $event ) {

    $event //= {};
    Cpanel::Server::SSE::cpanel::UserTasks::Event->adopt($event);

    return $self->_send_sse_message( $event->TO_JSON->%* );
}

1;
