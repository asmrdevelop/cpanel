package Cpanel::Systemd::Notify;

# cpanel - Cpanel/Systemd/Notify.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw( Cpanel::Destruct::DestroyDetector );

=encoding utf-8

=head1 NAME

Cpanel::Systemd::Notify

=head1 SYNOPSIS

    use Cpanel::Systemd::Notify ();

    sdnotify()->enable() if grep { /^--systemd/ } @ARGV;

    # ... get ready to do things ...
    sdnotify()->ready( 'Accepting requests...' );

    if ($got_reload_signal) {
        sdnotify()->reloading();
        # ... do reloading things ...
        sdnotify()->ready();
    }

    if ($got_stop_signal) {
        sdnotify()->stopping();
        # ... perform cleanup ...
        exit;
    }

    sub sdnotify {
        return Cpanel::Systemd::Notify->get_instance( 'service' => 'myservice' );
    }

=head1 DESCRIPTION

This class handles systemd notifications (see the L<sd_notify(3)> system manual page) for service daemons.

B<NOTE:> All public methods that would result in notifying systemd are no-ops until enabled by calling the L</enable()> method.
Therefore, it is safe to call all notification methods B<except> L</enable()> on non-systemd operating systems.
This is intended to simplify implementation of services that must work on non-systemd operating systems.

Most public methods return the object reference to allow method chaining. See the documentation for each method call for details.

=head1 SYSV TO NEW-STYLE SERVICE DAEMON CONVERSION RECOMMENDATIONS

These recommendations apply to new-style, non-forking services that run under systemd including those that use C<Type=notify> in the unit configuration.

See L<New-Style Daemons|https://www.freedesktop.org/software/systemd/man/daemon.html#New-Style%20Daemons> for a complete list of recommendations.

Most of the actions traditionally performed for SysV-style service startup can be categorized as either unnecessary or harmful.

The following items mostly address the harmful actions and at the very least should be addressed when converting or adding new-style service support to an existing SysV-style service:

=over

=item B<DON'T> fork() the main service process (i.e. Cpanel::Sys::Setsid::full_daemonize()) during service startup or hot restarts.

The B<main PID> should stay the same throughout the life of the service.
Performing a C<fork() && exit> during startup suffers from race conditions B<and> the process could at least temporarily lose permission to send systemd notifications until systemd guesses the new main PID again (if ever).

=item B<DON'T> call the L<setsid(2)> system call during service startup or hot restarts.

I<TLDR;> It does nothing but return an error which may then lead to an exception.

Systemd already invokes the main service process without a controlling TTY and as session leader, so L<setsid(2)> without a fork() first is redundant.
The designers of L<setsid(2)> decided that if the syscall doesn't need to do anything then it should fail with EPERM.
By itself that isn't a problem, but modules like C<Cpanel::Syscall> and C<Cpanel::Sys::Setsid> throw an exception on error.

=item B<DO> call the L</safe_disable()> or L</disable()> method on an inherited instance of this class in a forked child process as soon as possible.

Child processes of the service generally don't need to send notifications to systemd.
Permanently disabling the inherited instance ensures notifications can't be sent accidentally, and makes it slightly more difficult to send notifications maliciously because the environment variable holding the socket path is removed.

=item B<DO> set C<NotifyAccess> explicitly in the service's unit configuration.

When C<NotifyAccess> is not defined in the unit configuration it is forced to C<NotifyAccess=main> but the systemd authors do not intend for this behavior to be relied upon.
C<NotifyAccess=main> is the suggested setting.

=back

=head1 FUNCTIONS

=head2 CLASS->get_instance()

Constructs and caches one instance of the class per unique C<service> argument (a parametric singleton).
Arguments other than C<service> do not affect the uniqueness of an instance, but will be passed to the constructor the first time an instance is created.

An attempt will be made to destroy all cached instances in an orderly manner before Perl's global destruction phase, but this can only work if callers do not store the returned reference in a C<state> variable or a global variable.

Returns the object reference for the given C<service> parameter.

It is recommended to use C<get_instance()> to chain method calls without storing the reference, for example:

    CLASS->get_instance( 'service'  => 'myservice' )->ready();

To keep it simple, the C<get_instance()> call and its parameters can be abstracted to a subroutine in the caller's scope:

    sub sdnotify() {
        return CLASS->get_instance( 'service => 'myservice' );
    }

Which allows:

    sdnotify()->enable();
    [...]
    sdnotify()->ready();
    [...]

=head3 ARGUMENTS

Same as C<< CLASS->new() >>.

=cut

sub get_instance ( $class, %OPTS ) {
    state %stash;
    END { undef %stash; }
    if ( delete $OPTS{'_clear_instance_stash'} ) {    # For tests.
        undef %stash;
        return;
    }
    return $stash{ $class . q{_} . ( $OPTS{'service'} // 'no_service' ) } //= $class->new(%OPTS);
}

=head2 CLASS->new()

Object constructor.
Pass in arguments as a hash.

B<BE SURE> to C<undef> the returned object reference before the global destruction phase or a warning will be generated. Proper use of C<< CLASS->get_instance() >> can help with handling this automatically.

=head3 ARGUMENTS

=over

=item service - string

Required. The name of the service. Currently this is only used when generating exceptions.

=item require_xs - Boolean

Optional. Require the use of Linux::Systemd::Daemon::notify.
Cannot be used in combination with the C<use_fallback> option.
This should only be used for testing purposes.

=item use_fallback - Boolean

Optional. Do not use Linux::Systemd::Daemon::notify even if it is available and only call the external 'systemd-notify' binary.
Cannot be used in combination with the C<require_xs> option.
This should only be used for testing purposes.

=back

=head3 EXCEPTIONS

=over

=item When required arguments are missing.

=back

=cut

sub new ( $class, %OPTS ) {
    die 'The “service” parameter is required.' unless $OPTS{'service'};
    my $opts = {
        '_enable'      => 0,
        '_initial_pid' => $$,
        'require_xs'   => $OPTS{'require_xs'}   // 0,
        'use_fallback' => $OPTS{'use_fallback'} // 0,
        'service'      => $OPTS{'service'},
    };
    die 'The “require_xs” and “use_fallback” options are mutually exclusive.' if $opts->{'require_xs'} && $opts->{'use_fallback'};
    return bless $opts, $class;
}

=head2 enable()

Enable systemd notifications.

Returns the object reference.

=head3 EXCEPTIONS

=over

=item When the notify socket environment variable does not exist or does not contain a valid path to a socket.

=back

=cut

sub enable ($self) {
    $self->{'_enable'} = 1;
    $self->_ensure_socket_exists_if_enabled();
    return $self;
}

=head2 disable()

B<NOTE:> It is safer to use L</safe_disable()> for additional protection against accidentally disabling notifications in the main service process.

Disable systemd notifications and delete the environment variable that contains the path to the notification socket.
This is intended to be called by forked child processes that don't need to or shouldn't send systemd notifications.

Returns the object reference.

=head3 ARGUMENTS

=over

=item keep_env - boolean

Optional. Prevents deletion of the environment variable that contains the path to the notification socket.
This option should only be used if notifications need to be re-enabled later in the same process.

=back

=cut

sub disable ( $self, %opts ) {
    $self->{'_enable'} = 0;
    delete $ENV{ NOTIFY_SOCKET_ENV_KEY() } unless $opts{'keep_env'};
    return $self;
}

=head2 safe_disable()

This is identical to L</disable()> with an added safety measure.
It will B<not> disable notifications if the calling process PID matches the PID that instantiated the object.
This is intended to mitigate a potentially critical programming error where notifications are accidentally disabled for the remainder of the life of the main process.

Accepts the same arguments as L<disable()>.

=cut

sub safe_disable {
    my ( $self, %opts ) = @_;
    if ( $self->is_enabled() && $self->{'_initial_pid'} == $$ ) {
        _log_warn("safe_disable called from main process [$$]!");
        return $self;
    }
    goto &disable;
}

=head2 disable_for_cr($code_ref)

Similar to L</disable()>, but notifications will be disabled only in the context
of the provided code ref to be executed.  No arguments are passed to the code
ref, its return value is discarded, and exceptions are not trapped.

=cut

sub disable_for_cr ( $self, $cr ) {
    die 'The “$cr” parameter must be a code ref.' if ref $cr ne 'CODE';
    local $self->{'_enable'} = 0;
    delete local $ENV{ NOTIFY_SOCKET_ENV_KEY() };
    $cr->();
    return $self;
}

=head2 notify(%state)

This is to be used by a service daemon to notify systemd of its status.
A process will also need to have notification access as defined by C<NotifyAccess> in the service's unit configuration.
It is suggested that C<NotifyAccess=main> is explicitly defined in the unit configuration.

B<IMPORTANT:> If a process lacks access via NotifyAccess configuration then systemd will ignore the notification. No error will be generated!

Returns the object reference.

=head3 ARGUMENTS

Pass in any L<sd_notify(3)> state variables as named arguments. At least one argument is required.
Any key-value pairs are accepted and systemd will ignore what is not an exact match for a well-known state.

B<Unknown or invalid keys or values do not result in errors, only inaction.>
A typo, incorrect letter-case, or extra whitespace could result in the state variable being completely ignored.

Other methods (ready(), stopping(), status(), etc.) are available to hide these details for the most-used states.
Use those methods when possible.
Consider adding new methods for any needed states that are not already covered here instead of calling notify() directly.

See the L<sd_notify(3)> system manual page for more information about the available well-known states.

=head3 EXCEPTIONS

=over

=item When required arguments are missing.

=item When the notify socket environment variable does not exist or does not contain a valid path to a socket.

=item When the C<systemd-notify> command is missing or returns an error status.

=back

=cut

sub notify ( $self, %state ) {
    die 'The “%state” parameter is required.' unless keys %state;
    return $self                              unless $self->_ensure_socket_exists_if_enabled();
    my @args = _build_state_args( \%state );
    if ( my $xs_notify = $self->_get_xs_notify() ) {
        $xs_notify->( _build_state_block( \@args ) );
    }
    else {
        _run_systemd_notify( \@args );
    }
    return $self;
}

=head2 status($status)

Send a notification to systemd containing the well-known "STATUS=..." state.
Updates the service's human-friendly status string.

See L</notify(%state)> above for important information.

Returns the object reference.

=head3 ARGUMENTS

=over

=item Required. A single line of UTF-8 text.

=back

=cut

sub status ( $self, $status ) {
    return $self->notify( _build_status_args($status) );
}

=head2 ready()

Send a notification to systemd containing the well-known "READY=1" state.
This signifies that the calling process has completed startup.

See L</notify(%state)> above for important information.

Returns the object reference.

=head3 ARGUMENTS

=over

=item Optional. A single line of UTF-8 status text.

See L</status($status)>.
Defaults to B<'Ready'>

=back

=cut

sub ready ( $self, $status = undef ) {
    return $self->notify( 'READY' => 1, _build_status_args( $status // 'Ready' ) );
}

=head2 reloading()

Send a notification to systemd containing the well-known "RELOADING=1" state.
This signifies that the calling process is beginning to reload its configuration.

IMPORTANT: The process must call the ready() method when it is done reloading.

See L</notify(%state)> above for important information.

Returns the object reference.

=head3 ARGUMENTS

=over

=item Optional. A single line of UTF-8 status text.

See L</status($status)>.
Defaults to B<'Reloading...'>

=back

=cut

sub reloading ( $self, $status = undef ) {
    return $self->notify( 'RELOADING' => 1, _build_status_args( $status // 'Reloading...' ) );
}

=head2 stopping()

Send a notification to systemd containing the well-known "STOPPING=1" state.
This signifies that the calling process is beginning to shut down.

See L</notify(%state)> above for important information.

Returns the object reference.

=head3 ARGUMENTS

=over

=item Optional. A single line of UTF-8 status text.

See L</status($status)>.
Defaults to B<'Stopping...'>

=back

=cut

sub stopping ( $self, $status = undef ) {
    return $self->notify( 'STOPPING' => 1, _build_status_args( $status // 'Stopping...' ) );
}

=head2 is_enabled()

Returns true when notifications are enabled.

=cut

sub is_enabled ($self) {
    return $self->{'_enable'};
}

#----------------------------------------------------------------------

sub _ensure_socket_exists_if_enabled ($self) {
    return unless $self->is_enabled();
    my $socket = $ENV{ NOTIFY_SOCKET_ENV_KEY() };
    if ( !defined $socket ) {
        die 'The “' . NOTIFY_SOCKET_ENV_KEY() . '” environment variable is empty.';
    }
    if ( !-S $socket ) {
        die "The socket file “$socket” is missing.";
    }
    return 1;
}

sub _get_service ($self) {
    return $self->{'service'};
}

# Given a string, returns a key/value pair to set STATUS.
sub _build_status_args ($status) {
    die 'Must be list context!' unless wantarray;
    return length $status ? ( 'STATUS' => $status ) : ();
}

# Given a hash ref of states, returns an array of KEY=VALUE items suitable for feeding to _run_systemd_notify() as arguments, or transforming further with _build_state_block().
sub _build_state_args ($state_ref) {
    die 'Must be list context!' unless wantarray;
    return map { "$_=" . $state_ref->{$_} } sort keys $state_ref->%*;
}

# Given an array ref of KEY=VALUE items, returns a block of text suitable for feeding to the XS notify call.
sub _build_state_block ($args_ref) {
    return ( join "\n", $args_ref->@* ) . "\n";
}

sub _get_xs_notify ($self) {

    # See the sd_notify(3) manual page for more information about what this is calling.
    # Linux::Systemd::Daemon::notify($state) is a perl XS wrapper for libsystemd sd_notify(0, $state) and dies if that call's return value is <0.
    # Linux::Systemd::Daemon::notify has no return value and should be called in void context.
    return if $self->{'use_fallback'};
    $self->{'_xs_notify'} //= eval {
        require Linux::Systemd::Daemon;
        Linux::Systemd::Daemon->can('notify');
    };
    die 'The system is unable to load the required Linux::Systemd::Daemon::notify function.' if $self->{'require_xs'} && ref $self->{'_xs_notify'} ne 'CODE';
    return $self->{'_xs_notify'};
}

# For mocking
sub _system {
    return system(@_);
}

sub _run_or_die ( $program, $args_ref = [] ) {

    # Don't interfere with a daemon's existing child process handling.
    local $!;
    local $?;
    local $SIG{'CHLD'} = 'DEFAULT';

    # If not directed somewhere else then systemd will send STDOUT/STDERR to the service's journal
    my $err = _system( $program, $args_ref->@* );
    return if $err == 0;
    if ( $err == -1 ) {
        die "“$program” failed to execute: $!\n";
    }
    elsif ( my $signal = $err & 127 ) {
        my $with_coredump = $err & 128;
        die sprintf "“$program” died with signal %d, %s coredump\n",
          $signal, $with_coredump ? 'with' : 'without';
    }
    die sprintf "“$program” exited with value %d", $err >> 8;
}

sub _run_systemd_notify ($args_ref) {
    return _run_or_die( '/usr/bin/systemd-notify', $args_ref );
}

sub _log_warn ($msg) {
    require Cpanel::Debug;
    return Cpanel::Debug::log_warn($msg);
}

# A constant, not a public function. More lightweight than "use constant".
sub NOTIFY_SOCKET_ENV_KEY () { return 'NOTIFY_SOCKET'; }

1;
