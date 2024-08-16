package Cpanel::ServiceManager::Base;

# cpanel - Cpanel/ServiceManager/Base.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 MODULE

=head2 NAME

Cpanel::ServiceManager::Base

=head2 DESCRIPTION

This is the parent class for Cpanel::ServiceManager::Services namespace which implements a common set of interfaces
for dealing with both first and third party services on a cPanel system. While the interfaces in this namespace both
define a standard set of behaviors as well as provide a common set attributes, this should be considered a thin wrapper
around the underlying oeprating system's management of services.

initd systems will rely heavily on pidfile and process names for detecting and managing daemons wheras systemd systems
are completely managed by the systemd daemon.

Note: on systemd systems several attributes are functionally useless, for example pidfile and process name definitions.
systemd will track the lifetime of a process and is leveraged for detection and management operations.

=cut

use strict;
use warnings;

use parent 'Cpanel::Destruct::DestroyDetector';

use Try::Tiny;

use Getopt::Long ();    # Cpanel::RestartSrv lazy loads this, however all the restartsrv* binaries need this so preload for perlcc
use Moo;

use Cpanel::IONice                           ();
use Cpanel::Binaries                         ();
use Cpanel::Pkgr                             ();
use Cpanel::Chkservd::Tiny                   ();
use Cpanel::Exception                        ();
use Cpanel::LogCheck                         ();
use Cpanel::Logger                           ();
use Cpanel::Output                           ();
use Cpanel::RestartSrv                       ();
use Cpanel::RestartSrv::Lock                 ();
use Cpanel::RestartSrv::Systemd              ();
use Cpanel::Server::Type::Profile::Roles     ();
use Cpanel::Services::Enabled                ();
use Cpanel::ServiceManager::Manager::Initd   ();
use Cpanel::ServiceManager::Manager::Systemd ();
use Cpanel::TimeHiRes                        ();
use Cpanel::OS                               ();
use Cpanel::Config::LoadCpConf               ();

=head1 ATTRIBUTES

=head2 CORE

=over 2

=item * C<is_cpanel_service>

Designates that the service does not have its base configuration setup from systemd and instead has a
script or binary located (usually) in the /usr/local/cpanel tree.

Additionally, the object will forcibly invoke the initd manager when called from systemd's primary
daemon running as PID 1. This is because the logic for the daemon is contained here instead of the
systemd config.

Note: there will still be a systemd config in the standard places (/etc/systemd/system) but it merely
invokes scripts/restartsrv_$service as the authoritative daemon.

Specified by individual services.

=cut

has 'is_cpanel_service' => ( is => 'ro', lazy => 1 );

=item * C<processowner>

Intended system user that the service daemon will run as.

Defaults to root.

=cut

has 'processowner' => ( is => 'rw', default => 'root' );

=item * C<service>

The base name of the Cpanel::ServiceManager::Services module.

Specified by individual services.

=cut

# service should not be lazy as it needs to be set for the lock
has 'service' => ( is => 'rw', lazy => 1, builder => 1 );

=item * C<service_binary>

Specfies the location of the service's daemon.

Auto-computed via L<Cpanel::Binaries/path>.

=cut

has 'service_binary' => (
    is      => 'rw',
    lazy    => 1,
    default => sub {
        return eval { Cpanel::Binaries::path( lc( $_[0]->service() ) ) }
    }
);

=item * C<suspend_time>

The amount of seconds to tell chkservd that a service is not to be monitored when it's restarting.

Specified by individual services.

=back

=cut

has 'suspend_time' => ( is => 'rw', lazy => 1, default => 600 );

=head2 STATE

=over 2

=item * C<is_configured>

Some services may not be configured (the system being having that class of service disabled or using another
service to provide the functionality, ie various ftp, mail and name services).

This attribute is representative of whether a service is configured or not.

Note: not every service can be "unconfigured". Do not confuse configured for being enabled.

Auto-computed by individual services.

=cut

has 'is_configured' => ( is => 'rw', lazy => 1, default => 1 );

=item * C<not_configured_reason>

Optional reason explaining why the service is not configured.

=cut

has 'not_configured_reason' => ( is => 'rw', lazy => 1 );

=item * C<is_enabled>

Returns the whether or not a particular service is enabled or not.

It is strongly recommended to use this attribute instead of detecting the presence of the disable file
directly.

Note: this will use the cPanel standard /etc/${SERVICE}disable file by default but can be overridden by
individual service logic. Also note that some services may have various disable files!

State is dependent on external factors.

=cut

has 'is_enabled' => ( is => 'rw', lazy => 1, builder => 1 );

=item * C<has_single_pid>

boolean, default=1 to indicate if the process has a single MainPID

=cut

has 'has_single_pid' => ( is => 'ro', default => 1 );

sub _build_is_enabled {
    my ($self) = @_;

    return Cpanel::Services::Enabled::is_enabled( $self->service() ) ? 1 : 0;
}

=item * C<logger>

Returns an instance of L<Cpanel::Logger>.

=cut

has 'logger' => ( is => 'ro', lazy => 1, default => sub { return Cpanel::Logger->new(); } );

=item * C<lock>

Locks down a service so that only one instance is running on the server at a time.

Returns an instance of L<Cpanel::RestartSrv::Lock>.

=cut

# note: this is lazy to postpone it at BUILD time and being sure the service name is set
has 'lock' => ( is => 'rw', lazy => 1, builder => 1 );

sub _build_lock {
    my ($self) = @_;

    # acquire a lock at BUILD time

    # calling from systemd (or something REALLY crazy like single user/process that doesn't need locks) #
    # or not running as root... in that case we attempt our operation... likely a status call #
    return if getppid == 1 || $> != 0;

    my $service = $self->service // 'unknown';

    my $lock = Cpanel::RestartSrv::Lock->new($service)
      or die qq[The system failed to acquire a lock on the following service: $service];

    return $lock;
}

=item * C<service_argv_action>

Contains the action taken by the parseargv method.

Useful in situations where the caller asked for a difference action than was preformed.
For example: caller asked for a restart but the daemon was down and thus started instead.

Result of calling parseargv method.

=cut

# Prevent warnings by setting default of blank string
has 'service_argv_action' => ( is => 'rw', lazy => 1, default => "" );

=item * C<service_manager>

Dynamically instantiates an instance of the appropriate manager module.
Currently this can be one of: initd or systemd

Note: on systemd systems, this will forcibly return an instance of the initd module when called via systemd's
main daemon running as PID 1.

Returns an instance of L<Cpanel::ServiceManager::Manager>

=cut

has 'service_manager' => ( is => 'ro', lazy => 1, builder => 1 );

=item * C<service_name>

  A convenience attribute that returns the canonical name that should be used for external uses . For examples : calling systemctl / service or writing logs .

  Auto-computed based on service_override being set or not .

=cut

has 'service_name' => ( is => 'ro', lazy => 1, default => sub { return $_[0]->service_override() || $_[0]->service(); } );

=item * C<service_status>

Contains the result of the last status method call.

Result of calling status method.

=cut

has 'service_status' => ( is => 'rw', lazy => 1 );

=item * C<can_check_service_status>
by default we can check for the status of a service when it's a daemon,
but when the service is not a daemon, we cannot check its status on CentOS 5/6

boolean

=back

=cut

has 'can_check_service_status' => ( is => 'rw', lazy => 1, default => 1 );

=head2 OPTIONAL

=over 2

=item * C<doomed_rules>

When specified these are used to ensure the process has been terminated.

Note: these will be used on systemd systems only after systemd has reported an attempt to stop or restart
a service failed.

=cut

has 'doomed_rules' => ( is => 'rw', lazy => 1 );

=item * C<graceful_by_default>

When specified the service will use the graceful restart method if available by default. If the service
does not implement this method, then it'll fall back to the normal restart logic.

=cut

has 'graceful_by_default' => ( is => 'rw', lazy => 1, default => 1 );

=item * C<call_with_force>

This flag is set when called with --force from the command line

=cut

has 'call_with_force' => ( is => 'rw', lazy => 1, default => 0 );

=item * C<block_fresh_install>

When specified the service will refuse to startup if $ENV{'CPANEL_BASE_INSTALL'} is true
unless the --force flag is specified on the command line.

=cut

has 'block_fresh_install' => ( is => 'rw', lazy => 1, default => 0 );

=item * C<pidfile>

When specified the pidfile is used for detecting the service daemon in various situations (ie stopping it).

Note: on systemd systems this is unused as service status is tracked by systemd.

=cut

has 'pidfile' => ( is => 'rw', lazy => 1 );

=item * C<pid_exe>

When specified this will be used to find a service's daemons in the process table during check and various
management operations such as stop.

Note: on systemd systems this is unused as service status is tracked by systemd.

=cut

has 'pid_exe' => ( is => 'rw', lazy => 1 );

=item * C<ports>

When specified as an ARRAYREF, these ports will be used to both detect and manage a service.

Check functionality can use these ports to verify that a service's daemon is alive and responding to
requests.

On systemd systems the ports are only used for a service's daemon verification.

=cut

has 'ports' => ( is => 'rw', lazy => 1 );

=item * C<restart_args>

Species arugments (as an ARRAYREF) to use when the service's daemon is asked to restart.

=cut

has 'restart_args' => ( is => 'rw', lazy => 1 );

=item * C<service_override>

Overrides the service attribute. Useful for when entry points are not named the same as the module
in its namespace, for example:
scripts/restartsrv_foo actually invokes Cpanel::ServiceManager::Services::bar

Specified by individual services.

=cut

has 'service_override' => ( is => 'rw', lazy => 1 );

=item * C<service_pacakge>

When specified, the check method will verify that this RPM package is installed on the system.

Note: if specified and the RPM is not present on the system, it will cause an exception to be thrown
for many actions including (but not limited to): check, start and status.

=cut

has 'service_package' => ( is => 'rw', lazy => 1 );

=item * C<service_to_suspend>

Used to override the service name passed to chkservd to suspend when restarting a service.

=cut

has 'service_to_suspend' => ( is => 'rw', lazy => 1, default => sub { return $_[0]->service() } );

=item * C<startup_args>

Special arguments (as an ARRAYREF) to use when the service's daemon starts up.

=cut

has 'startup_args' => ( is => 'rw', lazy => 1 );

=item * C<shutdown_args>

Special arguments (as an ARRAYREF) to use when the service's daemon is asked to stop.

=cut

has 'shutdown_args' => ( is => 'rw', lazy => 1 );

=item * C<verbose>

Specifies that there should be verbose output to either standard out or cPanel's log facility.

Levels:
    0 - no output
    1 - standard out formatted for terminal or HTML output (@ARGV --html turns on HTML output)
    2 - cPanel log facility

=cut

has 'verbose' => ( is => 'rw', lazy => 1, default => 0 );

=item * C<restart_attempts>

Number of attempts to restart a service before throwing a fatal exception.

=cut

has 'restart_attempts' => ( is => 'rw', lazy => 1 );

=item * C<current_restart_attempt>

Used to force the restart attempt loop to a specific attempt number and then quit regardless of success.

Note: this is useful when a service invokes additional logic only on specific attempt numbers or the restart
attempts are being done via an external system such as chkservd.

=cut

has 'current_restart_attempt' => ( is => 'rw', lazy => 1 );

=item * C<support_reload>

Flag to indicate whether or not the service supports 'reload' functionality.

=cut

has 'support_reload' => ( is => 'ro', lazy => 1, default => 0 );

=item * C<command_line_regex>

A regex to pass to Cpanel::Services that is used to match the name of the process on the command line

=cut

has 'command_line_regex' => ( is => 'ro', lazy => 1 );

=item * C<startup_timeout>

The number of seconds to wait for a process's PID file to exist before
indicating failure.

=cut

has 'startup_timeout' => ( is => 'ro', lazy => 1, default => 10 );

=item * C<cpconf>

Provides the RO contents of cpanel.config. Take great caution if you want to alter these values.

=back

=cut

has 'cpconf' => ( is => 'ro', lazy => 1, default => sub { Cpanel::Config::LoadCpConf::loadcpconf_not_copy() } );

# private attributes #

# sub _called_from_restart is used to change visual and behaviors when called from restart vs directly to start/stop #
# in some cases we may want to mask the fact that we're calling start/stop from the restart sub #
# once sub _called_from_restart is called this flag resets to false #
has '_pretend_not_called_from_restart' => ( is => 'rw', lazy => 1, default => 0 );

has '_pid' => ( is => 'ro', default => sub { $$ } );

# use to disable output partial
has 'disable_output_partial' => ( is => 'rw', lazy => 1, default => 0 );

=head1 METHODS

=head2 OBJECT

=head3 BUILD

Sets up all service object base paramenters and state:
    - rlimits
    - locks the service
    - determines default attributes when not specified by service

B<Output>

    OBJECT - instance of a service object based on L<Cpanel::SerivceManager::Base>

=cut

sub BUILD {
    my ($self) = @_;

    # setup the environment's PATH to a known quantity #
    $self->debug('The system is setting up the environment PATH...');
    Cpanel::RestartSrv::setuppath();

    $self->lock;    # acquire the lock at build time, service need to be set

    return;
}

=head3 DESTROY

Cleans up any outstanding object internals, such as releasing the system wide lock on the service.

Note: only does specific work in the parent process.

=cut

sub DESTROY {
    my $self = shift;

    # we do not take a lock out when our parent is pid 1 (see above) #
    if ( $$ == ( $self->_pid // 0 ) && $self->{'lock'} ) {
        $self->lock->release();
    }

    return;
}

=head2 ACTIONS

=head3 run_from_argv

Main entry point for scripts/restartsrv and etc/init/(start|stop) scripts. Expects to parse @ARGV style
array of options to determine further action.

B<Input>

    ARRAY - @ARGV style options; see L<Cpanel::RestartSrv/parseargv> for specific options

=cut

sub run_from_argv {
    my ( $self, @argv ) = @_;

    # parse command line options #
    my ( $restart, $check, $status, $verbose, $current_restart_attempt, $graceful );
    {
        local @ARGV = @argv;
        ( $restart, $check, $status, $verbose, $current_restart_attempt, $graceful ) = Cpanel::RestartSrv::parseargv();

        $graceful = 0 if grep { $_ eq '--hard' } @argv;    # hard restart
        $self->call_with_force(1) if grep { $_ eq '--force' || $_ eq '-force' } @argv;

        $self->{'output_obj'} = Cpanel::RestartSrv::get_formatted_output_object(@argv);
    }

    # set some runtime flags #
    $self->verbose($verbose);

    # counter starts at 0
    $self->current_restart_attempt( $current_restart_attempt - 1 ) if defined $current_restart_attempt and $current_restart_attempt =~ m/^[0-9]+$/;

    my %exception_parameters = ( 'service' => $self->service() );

    # decide what we're going to do based on @ARGV parsing #
    if ( !$check && !$status ) {
        if ( $Cpanel::RestartSrv::STOP == $restart ) {
            $self->service_argv_action('STOP');
            $self->stop();
        }
        elsif ( $Cpanel::RestartSrv::RESTART == $restart ) {
            $self->service_argv_action('RESTART');
            my $succeeded = $self->restart( 'graceful' => $graceful );
            $self->_generate_restart_exception( \%exception_parameters )
              if !$succeeded;
        }
        elsif ( $Cpanel::RestartSrv::RELOAD == $restart && $self->support_reload() ) {
            $self->service_argv_action('RELOAD');
            my $succeeded = $self->reload();
            $self->_generate_reload_exception( \%exception_parameters )
              if !$succeeded;
        }
    }
    elsif ($check) {
        $self->service_argv_action('CHECK');

        my ( $check_ok, $check_message ) = $self->check_with_message();
        if ($check_ok) {
            chomp($check_message) if $check_message;
            print "The '" . $self->service() . "' service passed the check" . ( $check_message ? ': ' . $check_message : '' ) . "\n";
        }
    }
    elsif ($status) {
        $self->service_argv_action('STATUS');
        print $self->status();
    }
    else {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess('The system requested the unknown state from Cpanel::RestartSrv::parseargv().');
    }

    # no return code, this is intended to be "sub main" #
    return;
}

=head3 restart

Will either restart a running service daemon or start it. this is the main action as it were.

The function will check to see if call_with_force (--force was provided on the command line)
is set and prevent the service from starting during a cpanel install.

If cpanel_base_install is set and --force is called this function
will cause an exit since we do not want the restartsrv_base binary to
proceed.  this is not ideal, however it would require too much refactoring
to do otherwise at this point, and it follows the pattern of some of the
other services.

=cut

sub restart {    ## no critic(ProhibitExcessComplexity)
    my ( $self, %opts ) = @_;

    $self->_exit_if_block_fresh_install();

    my %exception_parameters = ( 'service' => $self->service() );

    # see if the service is down/not enabled, if not (ie not installed) then throw #
    my $is_running;
    try {
        $is_running = $self->status();
    }
    catch {

        # rethrow if exception if it's not down #
        die $_ if ref $_ ne 'Cpanel::Exception::Service::IsDown';
    };

    my $is_disabled                        = !$self->is_enabled();
    my $service_is_role_aware_and_disabled = $self->_service_is_role_aware_and_disabled();

    # It's common to disable and then stop a service.
    # So, if the service is up and disabled, or if the role is disabled,
    # then just call the stop routine.
    if ( ( $service_is_role_aware_and_disabled || $is_disabled ) && $is_running ) {

        # but do the stop action if the service is up #
        $self->service_argv_action('STOP');
        $self->_pretend_not_called_from_restart(1);
        return 0 if !$self->stop();

        if ($is_disabled) {

            # Let them know the service isn't coming back up,
            # and throw the disabled exception.
            $self->info( q{The service '} . $self->service() . q{' is disabled and the system will not attempt to restart it.} );
            $self->_generate_disabled_exception( \%exception_parameters );
        }

        # We got here because no active roles on the system need the service.
        my $err = $self->_no_roles_exception();
        $self->info( $err->to_string_no_id() );
        die $err;
    }

    if ( !$is_running ) {

        # we have to check the service sanity when its down to make sure it'll have the best chance of success #
        $self->debug( q{The system is verifying that the '} . $self->service() . q{' service is ready to start...} );

        # This will verify the role(s) for the service.
        $self->check_sanity();
        $self->_terminate_orphaned_processes();

        $self->output_partial( 'Waiting for “' . $self->service() . '” to start …' )
          if 1 == $self->verbose();
    }
    else {
        # Refuse to restart a service that no enabled roles need.
        $self->_no_roles_exception() if $service_is_role_aware_and_disabled;

        # make sure we can do restart the service at this point #
        $self->stop_check() if $self->can('stop_check');
    }

    if ( $is_running && $self->is_enabled() ) {

        # make sure we can do restart the service at this point #
        $self->stop_check() if $self->can('stop_check');

        # only if the service is up (and enabled) do we want to try to restart it #
        if ( $self->can('restart_check') ) {
            return 0 if !$self->restart_check();
        }

        my $graceful = defined $opts{'graceful'} ? $opts{'graceful'} : $self->graceful_by_default();
        if ( $self->is_enabled() && $self->can('restart_gracefully') && $graceful ) {
            if ( 1 == $self->verbose() ) {
                $self->output_partial("Waiting for “$self->{'service'}” to restart gracefully …");
            }
            else {
                $self->debug( q{The system is attempting to restart the '} . $self->service() . q{' service gracefully...} );
            }

            if ( $self->restart_gracefully() && $self->wait_for_service_status(0) ) {
                if ( 1 == $self->verbose() ) {
                    $self->output('…finished.');
                    $self->output('');
                }
                return 1;
            }

            # failed to restart gracefully, fall back to full restart #
            if ( 1 == $self->verbose() ) {
                $self->output('…failed.');
                $self->output('');
            }
            else {
                # We MUST always do a hard restart if a graceful one fails
                # see CPANEL-29044 for details
                $self->debug( q{The system failed to gracefully restart the '} . $self->service() . q{' service. The system is attempting to stop and then start the service...} );
            }
        }

        # the manager may have a method of restarting that works with the service binary directly #
        if ( $self->is_enabled() && $self->restart_args() && $self->service_manager()->can('restart') ) {
            if ( 1 == $self->verbose() ) {
                $self->output_partial( 'Waiting for “' . $self->service() . '” to restart …' );
            }
            else {
                $self->debug( q{The system is attempting to restart the '} . $self->service() . q{' service...} );
            }
            if ( $self->service_manager()->restart($self) && $self->wait_for_service_status(0) ) {
                if ( 1 == $self->verbose() ) {
                    $self->output('…finished.');
                    $self->output('');
                }
                return 1;
            }
            if ( 1 == $self->verbose() ) {
                $self->output('…failed.');
                $self->output('');
            }
        }
    }
    elsif ( !$is_running ) {

        # service wasn't running to begin with #
        $self->service_argv_action('START');
    }

    if ($is_running) {

        # the service is still running because one of the following reasons: #
        # - failed to gracefully restart #
        # - does not have a graceful restart functionality #
        if ( 1 == $self->verbose() ) {
            $self->output_partial("Waiting for “$self->{'service'}” to restart …");
        }
        else {
            $self->debug( q{The system is attempting to restart the '} . $self->service() . q{' service...} );
        }

        $self->stop();
    }

    # when the service is disabled, we just don't do anything #
    $self->_generate_disabled_exception( \%exception_parameters )
      if !$self->is_enabled();

    my $start_ok = $self->start();
    return 0 unless $start_ok;

    my $restart_status = $start_ok && $self->service_status();
    $self->debug( 'restart service "' . $self->service() . '": ' . ( $restart_status ? 'OK' : 'Fail' ) );

    return $restart_status;
}

sub _called_from_restart {
    my $self = shift;

    if ( $self->_pretend_not_called_from_restart() ) {
        $self->_pretend_not_called_from_restart(0);
        return 0;
    }

    my $called_from_restart = 0;
    for ( 2 .. 5 ) {
        my $stack_method = ( caller($_) )[3];
        last if !$stack_method;
        if ( $stack_method eq 'Cpanel::ServiceManager::Base::restart' ) {
            $called_from_restart = 1;
            last;
        }
    }
    return $called_from_restart;
}

sub resetnice {
    my ($self) = @_;
    $self->debug('The system is using default (maximum) nice values...');

    local $@;
    eval { setpriority( 0, 0, 0 ); };    # disable nice
    warn if $@;

    Cpanel::IONice::reset();

    return;
}

sub setrlimits {
    my ($self) = @_;
    $self->debug('The system is using default (maximum) environment rlimits...');

    require Cpanel::Rlimit::Unset;
    Cpanel::Rlimit::Unset::unset_rlimits();

    return;
}

=head3 start

Will either start a service daemon.

The function will check to see if call_with_force (--force was provided on the command line)
is set and prevent the service from starting during a cpanel install.

If cpanel_base_install is set and --force is called this function
will cause an exit since we do not want the restartsrv_base binary to
proceed.  this is not ideal, however it would require too much refactoring
to do otherwise at this point, and it follows the pattern of some of the
other services.

=cut

sub start {    ## no critic(ProhibitExcessComplexity)
    my $self = shift;

    # when called from the restart sub, we don't need to output first level of verbose initial status message #
    # (we'll still show the progress) #
    my $called_from_restart = $self->_called_from_restart();

    # when not called from restart (which independently decides when to check sanity) we should check_sanity fisrt #
    $self->check_sanity() if !$called_from_restart;

    $self->_terminate_orphaned_processes() if !$called_from_restart;

    my %exception_parameters = ( 'service' => $self->service() );
    return 0 unless $self->is_enabled();

    return 0 if $self->can('start_check') && !$self->start_check();

    $self->_exit_if_block_fresh_install();

    # make sure the log environment is good #
    $self->debug('The system is checking the log environment...');
    Cpanel::LogCheck::logcheck();

    $self->debug('The system is setting the umask...');
    umask 022;

    $self->debug('The system is setting rlimits for the service...');
    $self->setrlimits();

    $self->debug('The system is setting nice for the service...');
    $self->resetnice();

    if ( 1 == $self->verbose() && !$called_from_restart ) {
        $self->output_partial( 'Waiting for “' . $self->service() . '” to start …' );
    }
    else {
        $self->debug( q{The system is attempting to start the service '} . $self->service() . q{'...} );
    }

    # attempt to start the service as many times as it wants #
    my $started;
    my $restart_attempts     = $self->current_restart_attempt() || 0;
    my $max_restart_attempts = $self->restart_attempts()        || 1;

    # when ports are known give a bonus attempt by killing processes on port
    my $can_kill_apps_on_ports = scalar @{ $self->ports() || [] };
    ++$max_restart_attempts if $max_restart_attempts < 2 && $can_kill_apps_on_ports;

    while ( $restart_attempts < $max_restart_attempts || defined $self->current_restart_attempt() ) {

        $self->output_partial('…') if 1 == $self->verbose();

        if ($restart_attempts) {
            $self->debug( q{The service '} . $self->service() . qq{' failed to start $restart_attempts time(s).} );
            if ( $restart_attempts == 1 && $can_kill_apps_on_ports ) {
                $self->kill_apps_on_ports;
            }
            $self->service_manager()->restart_attempt( $self, $restart_attempts ) if $self->service_manager()->can('restart_attempt');

            # continue check/fixups #
            $self->restart_attempt($restart_attempts) if $self->can('restart_attempt');
        }

        # If the service has a PID file and it's not running, remove the PID
        # file so that simple systemd jobs can continue to run.  If it's already
        # running, don't do that, as we'll want to catch that in the daemon in
        # case systemctl falsely returns success.
        my $pidfile = $self->pidfile();
        unlink $pidfile if length $pidfile && -e $pidfile && !$self->is_up_via_pidfile();

        my $waited_for_status = 0;
        if ( $self->service_manager()->start($self) ) {

            # rely on start return when no pid file is provided
            if ( !$self->pidfile() || $self->is_up_via_pidfile() ) {
                if ( $self->wait_for_service_status($restart_attempts) ) {
                    $started = 1;
                    last;
                }
                $waited_for_status = 1;
            }
        }
        last if defined $self->current_restart_attempt();    # manual restart forcing restart_attempt cursor

        $restart_attempts++;
    }

    if ( !$started ) {
        if ( 1 == $self->verbose() ) {
            $self->output('…failed.');
            $self->output('');
        }
        $self->_generate_start_exception( \%exception_parameters );
    }

    if ( 1 == $self->verbose() ) {
        $self->output('…finished.');
        $self->output('');
    }

    return 1;
}

# This is a common logic for CentOS 5/6/7
sub kill_apps_on_ports {
    my ( $self, %opts ) = @_;

    $opts{'exclude_ips'} //= [];

    return unless scalar @{ $self->ports() || [] };

    $self->debug( q{The system is cleaning up any remaining processes using the service's ports: } . join( ', ', @{ $self->ports() } ) );

    require Cpanel::Kill::AppPort;
    Cpanel::Kill::AppPort::kill_apps_on_ports(
        'ports'       => $self->ports(),
        'verbose'     => $Cpanel::Kill::AppPort::VERBOSE,
        'exclude_ips' => $opts{'exclude_ips'},
    );

    return 1;
}

sub stop {
    my $self = shift;

    # when called from the restart sub, we don't need to output first level of verbose status messages #
    # (we'll still show the progress) #
    my $called_from_restart = $self->_called_from_restart();

    # If we are really running the init.d code when calling
    # from systemd we cannot do this check because
    # it will be the wrong one
    if ( !$self->service_manager()->this_process_was_executed_by_systemd() && !$self->is_up() ) {

        # if already stopped, we don't need to do anything else #
        if ( 1 == $self->verbose() && !$called_from_restart ) {
            $self->output( 'Service “' . $self->service() . '” is already stopped.' );
            $self->output('');
        }
        else {
            $self->debug( q{Service '} . $self->service() . q{' is already stopped.} );
        }
        return 1;
    }

    # make sure we can stop at this time #
    $self->stop_check() if $self->can('stop_check');

    if ( 1 == $self->verbose() && !$called_from_restart ) {
        $self->output_partial( 'Waiting for “' . $self->service() . '” to stop …' );
    }
    else {
        $self->debug( q{The system is attempting to stop the service '} . $self->service() . q{'...} );
    }

    # we don't want chksrvd to send alerts for a service that is intentionally down (for a short duration) #
    Cpanel::Chkservd::Tiny::suspend_service( $self->service_to_suspend(), $self->suspend_time );

    $self->output_partial('…') if 1 == $self->verbose();

    my $success = $self->service_manager()->stop($self);

    $self->_terminate_orphaned_processes() if !$called_from_restart;

    if ( 1 == $self->verbose() && !$called_from_restart ) {
        $self->output( $success ? '…finished.' : '…failed.' );
        $self->output('');
    }

    return $success;
}

sub reload {
    my $self = shift;

    my %exception_parameters = ( 'service' => $self->service() );

    # when the service is disabled, we just don't do anything #
    $self->_generate_disabled_exception( \%exception_parameters )
      if !$self->is_enabled();

    # Limit this call to the services explicitly configured to support reloads.
    return 1 if !$self->support_reload();

    my $out;
    try {
        $out = $self->status();

        # we have to check_sanity as an up service won't do this #
        $self->check_sanity() if $out;
    }
    catch {

        # rethrow if exception is not down, disabled or not configured #
        my $err                  = $_;
        my @allowable_exceptions = qw{Cpanel::Exception::Service::IsDown Cpanel::Exception::Services::Disabled Cpanel::Exception::Services::NotConfigured};
        die $err if !grep {
            try { $err->isa($_) }
        } @allowable_exceptions;
    };

    if ( defined $out && $out && $self->is_enabled() && $self->service_manager()->can('reload') ) {
        $self->logger()->info( q{The system is attempting to reload the '} . $self->service() . q{' service...} )
          if $self->verbose();
        return $self->service_manager()->reload($self);
    }

    return 1;
}

sub check_with_message {
    my ($self) = @_;

    local $self->{'_last_status'};

    # ->check may call ->status which
    # sets _last_status and allows us to
    # avoid two called to ->status since
    # they can be expensive

    # THIS FUNCTION MUST ALWAYS CALL ->check
    # BECAUSE ->check may be the child class.
    my $check = $self->check();

    # THIS FUNCTION MUST ALWAYS CALL ->status
    # BECAUSE ->status may be the child class.
    my $message = $self->{'_last_status'} || $self->get_status_string();    # we have to get status 2x because ->check can be overwritten by the child

    return ( $check, $message );
}

sub check {
    my ($self) = @_;

    my $out = $self->status();

    # we have to sanity check if the service is up as an up service won't do this via status #
    $self->check_sanity() if $out;

    return 1 if !$self->service_manager()->can('check');
    $self->debug("Checking service");
    return $self->service_manager()->check( $self, $out );
}

sub get_status_string {
    my ($self) = shift;

    # Don't bother if it isn't a daemon
    return sprintf( "Service '%s' is not a daemon, cannot check its status.\n", $self->service_name() ) if !$self->can_check_service_status;

    my $out;

    # Attempt to use "helper" pathway tied into systemd/initd if it exists
    if ( $self->service_manager()->can('status_helper') ) {

        # ask the helper to get the info #
        $out = $self->service_manager()->status_helper($self);
    }

    # No helper, so fallback to RestartSrv::check_service
    else {
        # standard method of getting info about the service's daemon #

        # only override when forcing initd #
        my $ignore_systemd;
        $ignore_systemd = 1 if grep { $_ eq '--initd' } @ARGV;

        $out = Cpanel::RestartSrv::check_service(
            'service'        => $self->service_name(),
            'user'           => $self->processowner(),
            'pidfile'        => $self->pidfile(),
            'ignore_systemd' => $ignore_systemd,
            'regex'          => $self->command_line_regex()
        );
    }

    return $out;
}

sub status {
    my ($self) = shift;

    my $called_from_restart = $self->_called_from_restart();

    my $out = $self->get_status_string();
    $self->service_status($out);

    $self->{'_last_status'} = $out;    # a hack to avoid calling status twice and keep compat with older service manager modules

    # if the service is running, we should just return that #
    return $out if $out;

    # if the service is down, we can complain (but only if we're not being called from the restart method, it'll check this manually) #
    $self->check_sanity() if !$called_from_restart;

    # and if it's just not running, well then ... #
    my %exception_parameters = ( 'service' => $self->service() );
    $self->_generate_is_down_exception( \%exception_parameters )
      if !$out;

    $self->{'_last_status'} = $out;    # a hack to avoid calling status twice and keep compat with older service manager modules
    return $out;
}

=head2 HELPERS

=head3 wait_for_service_status

Waits up to 30 seconds for a service to become ready as reported by calls to the check method.

B<Input>

    attempt - INTEGER; attempt number; primarily used for display purposes (only renders headers/verbose level 2 on first attempt (0))

=cut

sub wait_for_service_status {
    my ( $self, $p_attempt ) = @_;

    return 1 unless $self->can_check_service_status;

    if ( 0 == $p_attempt ) {
        if ( 1 == $self->verbose() ) {
            $self->output_partial( 'waiting for “' . $self->service() . '” to initialize …' );
        }
        else {
            $self->debug( q{The system is waiting for the '} . $self->service() . q{' service to initialize...} );
        }
    }

    $self->service_status(undef);

    my $status;
    my $start_timer = time();
    my $timer       = {};
    my $t           = 0;
    while ( $t < 120 ) {
        $self->output_partial('…') if 1 == $self->verbose() && !$timer->{$t};

        $status = eval { $self->status() };
        last if $status;

        $t = time() - $start_timer;

        if ( !$timer->{$t} ) {
            $self->debug( 'Waiting for service ' . $self->service() . ' to start for ' . $t . ' second(s)...' );
            $timer->{$t} = 1;
        }

        Cpanel::TimeHiRes::sleep(0.05);
    }

    $self->service_status($status);

    return $status;
}

=head3 check_sanity

Common routines to verify the service's environment to be sane.

Checks for: configured, enabled, RPM package installed and binary present

B<Output>

    BOOLEAN - true when all is well (throws an exception otherwise)

=cut

sub check_sanity {
    my $self = shift;

    my %exception_parameters = ( 'service' => $self->service() );

    $self->_verify_role();

    # check for common issues #
    if ( !$self->is_configured() ) {
        $self->_generate_not_configured_exception( { %exception_parameters, 'reason' => $self->not_configured_reason() } );
    }

    if ( $self->can_check_service_status() && !$self->is_enabled() ) {
        $self->debug( q{Service '} . $self->service() . q{' is disabled by touchfile: /etc/} . $self->service() . q{disable} )
          if -e '/etc/' . $self->service() . 'disable' && $self->verbose();
        $self->_generate_disabled_exception( \%exception_parameters );
    }

    if ( !$self->service_binary() || !-x $self->service_binary() ) {
        if ( $self->service_package() ) {
            $self->debug("Check sanity for service (package)");
            foreach my $service_package ( @{ ref( $self->service_package() ) eq ref( [] ) ? $self->service_package() : [ $self->service_package() ] } ) {
                my $version = Cpanel::Pkgr::get_package_version($service_package);

                if ( !defined $version || !length $version ) {
                    $self->info( qq{The system could not find required package '$service_package' for service '} . $self->service() . q{'...} )
                      if $self->verbose();
                    $self->_generate_not_installed_exception( \%exception_parameters );
                }
            }
        }
    }

    if ( $self->service_binary() && !-x $self->service_binary() ) {
        my $err = $! || 'Exists but not executable';
        $self->_generate_binary_not_found_exception( { %exception_parameters, 'binary' => $self->service_binary(), 'error' => $err } );
    }
    return 1;
}

=head3 is_up

Presents a very simple "is up" determination for callers.

Note: does not throw an exception unless something goes horribly wrong with determining
a service daemon's up status: this means it does NOT throw when the service is down!

B<Output>

    BOOLEAN - true/false as to whether the service daemon is up or not

=cut

sub is_up {
    my ( $self, %opts ) = @_;

    if ( my $is_up = $self->service_manager()->can('is_up') ) {
        return $is_up->( $self, %opts );
    }

    my $out = $self->get_status_string();    # We must use a single source of truth for the status string or we will disagree with ourselves about a service being up
    return $out && $out =~ m/\Q$opts{'via'}\E check method/ if $opts{'via'};
    return !!$out;
}

=head3 is_up_via_pidfile

Used to sanity check a service daemon's pidfile. Typically used after a start operation has been preformed.

Note: this will throw when there is a fatal problem detecting or reading the service daemon's pidfile!

B<Output>

    BOOLEAN - true/false as to whether a service daemon's pid is active

=cut

sub is_up_via_pidfile {
    my $self = shift;

    my $pidfile = $self->pidfile();

    # sanity #
    return 0 if !$pidfile;
    if ( !-d '/proc' ) {
        require Cpanel::Carp;
        die Cpanel::Carp::safe_longmess("The /proc filesystem must exist and be mounted.");
    }

    my $start_time;
    my $timeout = $self->startup_timeout;

    my $found_pidfile = 0;
    $start_time = time();
    while ( time() - $start_time <= $timeout ) {
        if ( -f $pidfile ) {
            $found_pidfile = 1;
            last;
        }
        Cpanel::TimeHiRes::sleep(0.05);
    }
    if ( !$found_pidfile ) {

        # suppress backtrace for this warning
        local $Cpanel::Logger::ENABLE_BACKTRACE = 0;

        # need to use the restart_attempt logic
        $self->logger->warn( q{The '} . $self->service() . q{' service's PID file '} . $self->pidfile() . qq{' did not appear after $timeout seconds.\n} );

        return 0;
    }

    $self->pidfile_precheck() if $self->can('pidfile_precheck');

    my $pid;
    for ( 1 .. 10 ) {
        $pid = undef;
        open my $pidfile_fh, '<', $pidfile or next;
        $pid = readline $pidfile_fh;
        next unless defined $pid;
        chomp $pid;
        $pid = int($pid);

        # we are going to reread the file if it's empty ( assuming it was not flushed )
        last if $pid;
    }
    continue {
        Cpanel::TimeHiRes::sleep(0.1);
    }

    return 0 unless $pid;

    # now make sure the process is there #
    return -d "/proc/$pid" ? 1 : 0;
}

=head3 INTERNAL

=cut

sub _build_service {
    my $self = shift;

    my $ref = ref $self;
    if ( $ref && $ref =~ m{^Cpanel::ServiceManager::Services::(.+)$} ) {
        return lc($1);
    }
    return;
}

# If we have a distro dependant / related name for this service, use it for systemd stuff ( i.e. crond => cron )
sub _get_systemd_name {
    my ($service_name) = @_;
    if ( Cpanel::OS::systemd_service_name_map()->{$service_name} ) {
        return Cpanel::OS::systemd_service_name_map()->{$service_name};
    }
    else {
        return $service_name;
    }

}

sub _build_service_manager {
    my ($self) = @_;

    # are we forcing to initd manager (either by request or mechanism)? #
    my $initd;
    $initd = Cpanel::ServiceManager::Manager::Initd->new( 'service' => $self->service_name, 'this_process_was_executed_by_systemd' => 1 )
      if ( grep { $_ eq '--initd' } @ARGV ) || 1 == getppid();

    if ( !$initd ) {

        # we're not running from the systemd daemon, we have not been asked for an initd manager... #
        # ... so see if the service is a systemd one now #
        my $systemd_service_name = _get_systemd_name( $self->service_name );
        my $service_via_systemd  = Cpanel::RestartSrv::Systemd::has_service_via_systemd($systemd_service_name);
        if ($service_via_systemd) {
            return Cpanel::ServiceManager::Manager::Systemd->new( 'service' => $systemd_service_name, 'service_via_systemd' => $service_via_systemd );
        }

        if ( Cpanel::OS::is_systemd() && !$ENV{'CPANEL_BASE_INSTALL'} ) {
            $self->logger()->warn( q{The system is unable to find systemd configuration for the '} . $self->service_name() . q{' service...} );
        }
    }

    $initd //= Cpanel::ServiceManager::Manager::Initd->new( 'service' => $self->service_name );

    return $initd;
}

sub _generate_start_exception {
    my ( $self, $exception_parameters ) = @_;

    die Cpanel::Exception::create( 'Services::StartError', $exception_parameters );    ## no extract maketext (variable is metadata; the default message will be used)
}

sub _generate_restart_exception {
    my ( $self, $exception_parameters ) = @_;

    die Cpanel::Exception::create( 'Services::RestartError', $exception_parameters );    ## no extract maketext (variable is metadata; the default message will be used)
}

sub _generate_reload_exception {
    my ( $self, $exception_parameters ) = @_;

    die Cpanel::Exception::create( 'Services::ReloadError', $exception_parameters );     ## no extract maketext (variable is metadata; the default message will be used)
}

sub _generate_is_down_exception {
    my ( $self, $exception_parameters ) = @_;

    # This is a case where the exception is not very exceptional
    # and we expect to throw it as part of the normal execution
    # of checking a service before starting it up.  Since the
    # check runs in a loop the backtrace generation gets very
    # expensive and results in high cpu while waiting for the
    # service to startup.  In order to address this we now
    # suppress the stack trace generation until we can refactor
    # this exception out of the happy path in the “status” function.
    my $suppress = Cpanel::Exception::get_stack_trace_suppressor();
    die Cpanel::Exception::create( 'Service::IsDown', $exception_parameters );    ## no extract maketext (variable is metadata; the default message will be used)
}

sub _generate_disabled_exception {
    my ( $self, $exception_parameters ) = @_;

    die Cpanel::Exception::create( 'Services::Disabled', $exception_parameters );    ## no extract maketext (variable is metadata; the default message will be used)
}

sub _generate_not_configured_exception {
    my ( $self, $exception_parameters ) = @_;

    die Cpanel::Exception::create( 'Services::NotConfigured', $exception_parameters );    ## no extract maketext (variable is metadata; the default message will be used)
}

sub _generate_not_installed_exception {
    my ( $self, $exception_parameters ) = @_;

    die Cpanel::Exception::create( 'Services::NotInstalled', $exception_parameters );     ## no extract maketext (variable is metadata; the default message will be used)
}

sub _generate_binary_not_found_exception {
    my ( $self, $exception_parameters ) = @_;

    die Cpanel::Exception::create( 'Service::BinaryNotFound', $exception_parameters );    ## no extract maketext (variable is metadata; the default message will be used)
}

sub output {
    my ( $self, $output ) = @_;

    return $self->{'output_obj'}->out( $output, $Cpanel::Output::SOURCE_LOCAL, $Cpanel::Output::COMPLETE_MESSAGE );
}

sub output_partial {
    my ( $self, $output ) = @_;

    return if $self->disable_output_partial;
    return $self->{'output_obj'}->out( $output, $Cpanel::Output::SOURCE_LOCAL, $Cpanel::Output::PARTIAL_MESSAGE );
}

sub info {
    my ( $self, @what ) = @_;

    if ( $self->is_debug_enabled ) {
        return $self->debug(@what);
    }

    $self->logger->info(@what);

    return;
}

sub warn {
    my ( $self, @what ) = @_;

    if ( $self->is_debug_enabled ) {
        return $self->debug(@what);
    }

    $self->logger->warn(@what);

    return;
}

sub is_debug_enabled {
    my ($self) = @_;

    return $self->verbose == 2;
}

{
    my $start;

    sub debug {
        my ( $self, @what ) = @_;

        return unless $self->is_debug_enabled;

        $start ||= Cpanel::TimeHiRes::time();
        my $delta = sprintf( "%.2f", Cpanel::TimeHiRes::time() - $start );
        $self->logger->info( join( ' ', "[ $delta sec ]", @what ) );

        return;
    }
}

sub _service_is_role_aware_and_disabled {
    return Cpanel::Server::Type::Profile::Roles::is_service_allowed( $_[0]->service() ) ? 0 : 1;
}

sub _verify_role {

    # Only do this once, not every time check_sanity
    # is called in the wait_for_service_status loop
    return if $_[0]->{'_verify_role'};
    if ( $_[0]->_service_is_role_aware_and_disabled() ) {
        $_[0]->_no_roles_exception();
    }
    $_[0]->{'_verify_role'} = 1;
    return;
}

sub _no_roles_exception {
    my ($self) = @_;
    die Cpanel::Exception::create( 'Service::IsUnused', [ service => $self->service_name() ] );
}

sub _exit {
    my ($code) = @_;
    return exit($code);
}

# Tested directly because refactoring
# start/restart is too large
sub _exit_if_block_fresh_install {
    my ($self) = @_;
    if ( $ENV{CPANEL_BASE_INSTALL} && $self->block_fresh_install() && !$self->call_with_force() ) {
        $self->info( $self->service_name() . ' start is blocked during fresh install, use --force' );
        _exit(0);
        return 1;    # return after _exit is for testing
    }
    return undef;
}

sub _terminate_orphaned_processes {
    my ($self) = @_;

    # If we're on systemd, and the service is owned by systemd, which thinks it's down,
    # when there's a process already running, then that's an insane state, as the process
    # was started outside systemd--shoot the other instance down for a clean restart.
    # (see CPANEL-17072)
    my $systemd_status = $self->service_manager()->can('service_via_systemd') ? $self->service_manager()->service_via_systemd() : undef;

    # $systemd_status should be a hashref, or zero.
    if ( $systemd_status && $systemd_status->{'SubState'} && ( $systemd_status->{'SubState'} eq 'dead' ) ) {

        # systemd owns it, but thinks it's down
        if ( Cpanel::RestartSrv::doomedprocess( $self->doomed_rules(), $self->is_debug_enabled() ) ) {

            # we found it, and gunned it.
            $self->info( q{All other attempts to stop the service have failed. The system successfully used an internal function to stop the service '} . $self->service_name . q{'.} );
        }
    }
    return;
}

1

__END__

=head1 MISC

=head2 SEE ALSO

L<Cpanel::ServiceManager::Manager::Initd>, L<Cpanel::ServiceManager::Manager::Systemd>, L<Cpanel::RestartSrv>
