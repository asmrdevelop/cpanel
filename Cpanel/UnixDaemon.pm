package Cpanel::UnixDaemon;

# cpanel - Cpanel/UnixDaemon.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use IO::Select       ();
use IO::Socket::UNIX ();

use Cpanel::Logger::Persistent        ();
use Cpanel::FHUtils::Blocking         ();
use Cpanel::Wait::Constants           ();
use Cpanel::MemUsage::Daemons::Banned ();
use Cpanel::Services::Hot             ();
use Cpanel::Systemd::Notify           ();

=head1 NAME

Cpanel::UnixDaemon - A common base class for daemons that listen on a unix domain socket

=head1 USES

This class may be useful if you want to implement a new daemon for which all of the following are true:

=over

=item * Uses a unix domain socket for servicing requests (not TCP or UDP)

=item * Launches a single child process per request

=item * Handles socket-level communication directly in its own implementation; does not need a protocol abstraction layer

=back

For a couple of example implementations, see:

=over

=item * cpgreylistd (via Cpanel::GreyList::Daemon)

=back

=head1 CONSTRUCTION

=head2 Note

You may not directly instantiate Cpanel::UnixDaemon. You must use a subclass that completes
the implementation.

=head2 Parameters

max_child_procs - Number - (Optional) If provided, use this number as the maximum number of
children to launch for servicing requests. If not provided, the default of 5 processes will
be used.

timeout_for_chld - Number - (Optional) If provided, use this as the number of seconds that
a child (connection handler) process will be allowed to live. If not provided, the default
of 5 seconds will be used.

debug - Boolean - (Optional) If provided, the stdout and stderr file descriptors will not be
closed when starting the daemon. Child classes may then provide diagnostic output based on the
debug attribute if needed.

=cut

sub new {
    my ( $package, $config_hr ) = @_;

    Cpanel::MemUsage::Daemons::Banned::check();

    if ( $package eq __PACKAGE__ ) {
        _croak( 'You may not instantiate the ' . __PACKAGE__ . ' class directly. Please use a subclass.' );
    }

    my $name         = $package->NAME();
    my $pretty_name  = $package->PRETTY_NAME();
    my $restart_func = $package->RESTART_FUNC();

    my $self = {
        name             => $name,
        pretty_name      => $pretty_name,
        restart_func     => $restart_func,
        timeout_for_chld => $config_hr->{timeout_for_chld} || 5,
        max_num_of_chld  => $config_hr->{max_child_procs}  || 5,
        start            => time(),
        debug            => $config_hr->{debug},
        sdnotify         => $config_hr->{sdnotify},
    };

    return bless $self, $package;
}

=head1 INTERFACE

=head2 start_daemon(LISTEN_FD)

This method starts the daemon.

This is the only public interface that callers should use after constructing an instance.

=cut

sub start_daemon {
    my ( $self, $listen_fd, $accepted_fd ) = @_;

    print "[*] Starting $self->{pretty_name} ...\n";
    $self->_sdnotify()->enable() if $self->{sdnotify};
    return $self->_start_processor( $listen_fd, $accepted_fd );
}

=head1 METHODS THAT MUST BE IMPLEMENTED

=head2 NAME()

Returns a short, lowercase name for the daemon.

=cut

my $MAX_FILEHANDLES_EXPECTED_TO_BE_OPEN = 1000;

sub NAME {
    return _croak('You must specify a daemon name.');
}

=head2 PRETTY_NAME()

Returns a short descriptive name for the daemon (may be multiple words).

=cut

sub PRETTY_NAME {
    return _croak('You must specify a pretty name.');
}

=head2 RESTART_FUNC()

Returns a function to be called during restarts. The returned function should accept
a single argument which will either be empty or contain a file descriptor number for
an existing listener socket. If the file descriptor is passed, then the returned
function should use it to reestablish its own listener socket. This would most likely
be implemented as an exec call where the file descriptor number is passed as an
argument to the daemon.

=cut

sub RESTART_FUNC {
    return _croak('You must specify a restart function.');
}

=head2 PID_FILE()

The path to a pid file to use for this daemon.

=cut

sub PID_FILE {
    return _croak('You must specify a PID file.');
}

=head2 LOGFILE()

The path to a log file to use for this daemon.

=cut

sub LOGFILE {
    Carp::confess('You must specify a log file.');
}

=head2 _read_request(SOCKET)

The subclass must override the _read_request method to implement a working daemon.

The implementation of this method must read a request from SOCKET and return two values:
One string containing the name of the operation and one array ref containing any data or
arguments associated with that operation.

=cut

sub _read_request {
    my ($self) = @_;
    die 'You must override the _read_request method.';
}

=head2 _handle_request(OP, DATA)

The subclass must override the _handle_request method to implement a working daemon.

The implementation of this method must take two arguments, the operation string and data
array ref returned by _read_request, and perform the requested operation using that data.
It must then return a string containing the response to send back to the client (including
terminating newline, if applicable). If it returns undef instead, then the connection will
be closed without any reply.

=cut

sub _handle_request {
    my ($self) = @_;
    die 'You must override the _handle_request method.';
}

=head2 _set_socket_permissions()

The subclass must override the _set_socket_permissions method to implement a working daemon.

The implementation should retrieve the socket path via $self->SOCKET_PATH() and then
chown/chmod this socket as needed. This allows for control over which users on the server
will be able to establish connections to the daemon.

=cut

sub _set_socket_permissions {
    die 'You must override the _set_socket_permissions method.';
}

=head1 METHODS THAT MAY OPTIONALLY BE IMPLEMENTED

=head2 SECONDS_BEFORE_GOING_DORMANT

The number of seconds to wait for a request to come in before entering dormant mode.

=cut

sub SECONDS_BEFORE_GOING_DORMANT {
    return 0;    # can_read(0) means wait forever and never enter dormant mode
}

=head2 _enter_dormant_mode(LISTEN_FD)

Subclasses may override this method, but they are not required to. If overridden, the provided
implementation will be triggered from the main process after a period of idle time (see
SECONDS_BEFORE_GOING_DORMANT).

The argument LISTEN_FD is the file decriptor of the listener socket, which must be passed to
the dormant version.

=cut

sub _enter_dormant_mode {
    return 1;
}

=head2 _periodic_task

Subclasses may override this method, but they are not required to. If overridden, the provided
implementation will be triggered from the main process via a SIGALRM handler. The first call
happens automatically after a fixed amount of time after daemon startup, and then it's up to
your implementation of _periodic_task to reset the alarm to the actual desired time after it
runs.

This may be used to perform some type of cleanup or other routine tasks.

=cut

sub _periodic_task {
    return 1;
}

=head2 _cleanup()

Subclasses may override this method, but they are not required to. If overridden, the provided
implementation will be called when the daemon is shutting down.

=cut

sub _cleanup {
    return 1;
}

=head1 INTERNAL METHODS - Do not call

=head2 _start_processor()

This method sets up the daemon's initial state before entering the main loop.

=cut

sub _start_processor {
    my ( $self, $listen_fd, $accepted_fd ) = @_;

    local $0 = "$self->{name} - processor";
    $self->{'logger'} = $self->_init_logger();

    # pid_file_no_unlink() returns
    # undef if pid in PID_FILE is running
    # 0 if failure due to read/write failure, sets $!
    # 1 if success
    if ( my $pid = Cpanel::Services::Hot::is_pid_file_active( $self->PID_FILE ) ) {
        print "[!] $self->{pretty_name} is already running with PID: '$pid'\n";
        exit 0;
    }
    elsif ( !Cpanel::Services::Hot::make_pid_file( $self->PID_FILE ) ) {
        $self->{'logger'}->die("Unable to write $self->PID_FILE file: $!");
    }
    $self->{'logger'}->info("$self->{pretty_name} Processor startup with PID '$$'");

    # If we are doing a graceful restart make sure we update the pid file time
    utime( undef, undef, $self->PID_FILE ) or $self->{'logger'}->die("Unable to update mtime on $self->PID_FILE file: $!");

    my $listener = $self->_init_socket($listen_fd);
    $self->_close_std_handles() unless $self->{debug};
    $self->_sdnotify()->ready();
    if ( !$self->_main_loop( $listener, $accepted_fd ) ) {
        return 1;
    }

    return;
}

=head2 main_loop()

This method starts the main listen/accept loop of the daemon.

=cut

sub _main_loop {
    my ( $self, $listener, $accepted_fd ) = @_;

    my ( $self_pipe_read_handle, $self_pipe_write_handle ) = _generate_selfpipe();

    $self->{self_pipe_read_handle}  = $self_pipe_read_handle;
    $self->{self_pipe_write_handle} = $self_pipe_write_handle;

    my $ALRM_SINGLE_DIGIT_NUMBER = 1;
    my $CHLD_SINGLE_DIGIT_NUMBER = 2;
    my $HUP_SINGLE_DIGIT_NUMBER  = 3;
    my $TERM_SINGLE_DIGIT_NUMBER = 4;
    my $USR1_SINGLE_DIGIT_NUMBER = 5;

    local $SIG{'ALRM'} = sub { syswrite( $self_pipe_write_handle, $ALRM_SINGLE_DIGIT_NUMBER ); };
    local $SIG{'CHLD'} = sub { syswrite( $self_pipe_write_handle, $CHLD_SINGLE_DIGIT_NUMBER ); };
    local $SIG{'HUP'}  = sub { syswrite( $self_pipe_write_handle, $HUP_SINGLE_DIGIT_NUMBER ); };
    local $SIG{'TERM'} = sub { syswrite( $self_pipe_write_handle, $TERM_SINGLE_DIGIT_NUMBER ); };
    local $SIG{'USR1'} = sub { syswrite( $self_pipe_write_handle, $USR1_SINGLE_DIGIT_NUMBER ); };

    # Set an 'early' alarm to run the first _periodic_task()
    # soon after (re)starting the daemon.
    _alarm(15);

    # This is coming from the dormant mode listener
    if ($accepted_fd) {
        $self->{'socket'} = IO::Socket::UNIX->new_from_fd( $accepted_fd, '+<' );
        if ( !$self->{'socket'} ) {
            $self->{'logger'}->die( "Failed to open fd: " . $! );
        }
        $self->_handle_accepted_socket || return 0;    # Unexpected exit
    }

    my $last_event_time = time;
    while (1) {
        my $selector = IO::Select->new( $self_pipe_read_handle, $listener );
        if ( my @ready_sockets = $selector->can_read(2) ) {
            $last_event_time = time;
            foreach my $ready_socket (@ready_sockets) {
                if ( $ready_socket == $self_pipe_read_handle ) {
                    my $signal_type;
                    if ( sysread( $self_pipe_read_handle, $signal_type, 1 ) ) {
                        if ( $signal_type == $ALRM_SINGLE_DIGIT_NUMBER ) {
                            $self->_periodic_task();
                        }
                        elsif ( $signal_type == $CHLD_SINGLE_DIGIT_NUMBER ) {
                            $self->{'children_count'}--;
                            1 while waitpid( -1, $Cpanel::Wait::Constants::WNOHANG ) > 0;
                        }
                        elsif ( $signal_type == $HUP_SINGLE_DIGIT_NUMBER || $signal_type == $USR1_SINGLE_DIGIT_NUMBER ) {
                            $self->{'logger'}->info('SIGHUP received: re-execing daemon');
                            $self->_sdnotify()->reloading();

                            $self->{restart_func}->( $listener->fileno, $self->_restart_args_ar() ) or do {
                                $self->{'logger'}->warn("Failed to restart $self->{pretty_name} by exec: $!");
                            };
                        }
                        elsif ( $signal_type == $TERM_SINGLE_DIGIT_NUMBER ) {
                            $self->{'logger'}->info("processor shutdown via SIGTERM with pid $$");
                            $self->_sdnotify()->stopping();
                            unlink $self->PID_FILE if Cpanel::Services::Hot::is_pid_file_self_or_dead( $self->PID_FILE );
                            $self->_cleanup();
                            return 1;
                        }
                        else {
                            $self->{'logger'}->info("Unexpected message from self pipe: $signal_type");
                            return 0;    # Unexpected signal
                        }
                    }
                }
                else {
                    $self->{'socket'} = $ready_socket->accept();

                    if ( $self->{'socket'} ) {
                        $self->_handle_accepted_socket || return 0;    # Unexpected exit
                    }
                }
            }
        }
        elsif ( time() - $last_event_time >= $self->SECONDS_BEFORE_GOING_DORMANT ) {
            $self->_enter_dormant_mode( fileno($listener) );
        }
    }

    return 1;
}

=head2 _handle_accepted_socket()

This method launches a child to handle a connection.

=cut

sub _handle_accepted_socket {
    my $self = shift;

    my $handler = sub {
        $self->{'socket'}->autoflush();
        $self->_handle_one_connection();
    };

    if ( ( $self->{'children_count'} || 0 ) >= $self->{max_num_of_chld} ) {
        wait();
    }

    if ( my $pid = fork() ) {
        $self->{'children_count'}++;
        $self->{'socket'}->close();
    }
    elsif ( defined $pid ) {
        local $0 = "$self->{name} - processing request";
        $self->_sdnotify()->safe_disable();
        $handler->();
        exit 0;
    }
    else {
        $self->{'logger'}->warn("Failed to fork(): $!\n");
        return 0;
    }

    return 1;
}

=head2 _handle_one_connection()

This method runs the handler for a request.

=cut

sub _handle_one_connection {
    my $self = shift;

    my $line;
    my $orig_time = _alarm( $self->{timeout_for_chld} );
    local $SIG{'ALRM'} = sub {
        $self->{'logger'}->die("Timeout while waiting for response on request: ['$line']");
    };

    eval {
        my ( $op, @data ) = $self->_read_request( $self->{'socket'} );

        my $reply = $self->_handle_request( $op, \@data );

        $self->{'socket'}->print($reply) if defined $reply;

        alarm $orig_time;
    };
    my $exception = $@;

    # This duplicate alarm line is needed to cover the case where we broke out of the eval without hitting the final line.
    # The alarm inside the eval is required to cover the case where the alarm would have gone off a tiny fraction of a second
    # after leaving the eval.
    alarm $orig_time;

    $self->{'socket'}->shutdown(2);
    $self->{'socket'}->close;

    die $exception if $exception;

    return;
}

=head2 _init_socket(LISTEN_FD)

This method initializes the unix domain socket for accepting connections.

=cut

sub _init_socket {
    my ( $self, $listen_fd ) = @_;

    local $^F = $MAX_FILEHANDLES_EXPECTED_TO_BE_OPEN;    #prevent cloexec

    my $listener;
    if ($listen_fd) {
        eval { $listener = IO::Socket::UNIX->new_from_fd( $listen_fd, '+<' ); };
        if ( !$listener || $@ ) {
            $self->{'logger'}->die( "Failed to open fd: " . ( $@ || $! ) );
        }
    }
    else {
        unlink $self->SOCKET_PATH;
        $listener = IO::Socket::UNIX->new(
            Type   => Socket::SOCK_STREAM(),
            Local  => $self->SOCKET_PATH,
            Listen => Socket::SOMAXCONN(),
        ) or $self->{'logger'}->die("Failed to create unix socket '@{[$self->SOCKET_PATH]}': $!");

        $self->_set_socket_permissions();
    }

    return $listener;
}

=head2 _sdnotify()

This method returns a parameterized singleton of Cpanel::Systemd::Notify which is unique per L<NAME()>.

=cut

sub _sdnotify ($self) {
    return Cpanel::Systemd::Notify->get_instance( 'service' => $self->NAME() );
}

=head2 _restart_args_ar()

This method returns an array reference containing additional arguments to be passed to L<RESTART_FUNC>.

=cut

sub _restart_args_ar ($self) {
    my @args;
    push( @args, '--systemd' ) if $self->{'sdnotify'};
    return \@args;
}

#####################################

sub _close_std_handles {
    my $self = shift;

    require Cpanel::CloseFDs;
    return Cpanel::CloseFDs::redirect_standard_io_dev_null();
}

#####################################

# For more info on self-pipes
# http://cr.yp.to/docs/selfpipe.html
# http://www.sitepoint.com/the-self-pipe-trick-explained/
sub _generate_selfpipe {
    my ( $self_pipe_read_handle, $self_pipe_write_handle );
    pipe( $self_pipe_read_handle, $self_pipe_write_handle ) || CORE::die("Could not generate self-pipe: $!");

    Cpanel::FHUtils::Blocking::set_non_blocking($self_pipe_read_handle);
    Cpanel::FHUtils::Blocking::set_non_blocking($self_pipe_write_handle);

    return ( $self_pipe_read_handle, $self_pipe_write_handle );
}

sub _init_logger {
    my ($self) = @_;
    return Cpanel::Logger::Persistent->new( { 'alternate_logfile' => $self->LOGFILE() } );
}

sub _alarm {
    my ($time) = @_;
    return alarm $time;
}

sub _croak {
    require Carp;
    *_croak = *Carp::croak;
    goto \&Carp::croak;
}

1;
