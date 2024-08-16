package Cpanel::ServiceManager::Manager::Systemd;

# cpanel - Cpanel/ServiceManager/Manager/Systemd.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Moo;

use Cpanel::SafeRun::Object     ();
use Cpanel::RestartSrv          ();
use Cpanel::RestartSrv::Systemd ();

has 'service'                              => ( is => 'rw', required => 1 );
has 'this_process_was_executed_by_systemd' => ( is => 'rw', lazy     => 1, default => 0 );
has 'service_via_systemd'                  => ( is => 'rw', lazy     => 1 );

#overwritten in tests
our $gl_systemctl_binary = '/usr/bin/systemctl';

sub BUILD {
    my ($self) = @_;
    die q{The system refused to recursively call systemctl for the '} . $self->service() . q{' service.}
      if 1 == getppid();
    return $self;
}

# If we override is_up we can get two different answer about a service
# being up so lets just have one single source of truth and let
# Cpanel::ServiceManager::Manager::Base use the same internals for
# status, check, and isup
# sub is_up {} # don't override - This left as a placeholder to associate with the above warning comment

sub start {
    my ( $self, $service ) = @_;

    open my $fh, '>', \( my $output = q<> ) or die "open/scalar: $!";

    # we really want to use restart here instead of start
    #   when a service is running under systemd vision and is killed badly
    #   systemd will think that the service is still alive whereas it's not
    #   it's all the more true when an ExecStop is defined, which is the case for all init.d scripts...
    my $run = Cpanel::SafeRun::Object->new(
        'program' => $gl_systemctl_binary,
        'args'    => [ 'restart', $self->service() . '.service', '--no-ask-password' ],
        stdout    => $fh,
        stderr    => $fh,
    );

    my $service_name = $self->service();

    #We should always report failures here.
    if ( $run->CHILD_ERROR() ) {
        my $autopsy = $run->autopsy();
        $service->info(qq{systemd failed to start the service “$service_name” ($autopsy): $output});
    }

    #Only report success if we want verbose details.
    elsif ( $service->is_debug_enabled() ) {
        $service->info(qq{systemd started the service “$service_name”.});
    }

    return !$run->CHILD_ERROR();
}

sub reload {
    my ( $self, $service ) = @_;

    my $run = Cpanel::SafeRun::Object->new(
        'program' => $gl_systemctl_binary,
        'args'    => [ 'reload', $self->service() . '.service' ]
    );
    my $error_code = $run->error_code();

    if ($error_code) {
        $service->debug( q{The system could not use the systemd daemon to reload the '} . $self->service() . qq{' service: $error_code} );
    }
    else {
        $service->debug( q{The system successfully used systemd to reload the '} . $self->service() . q{' service.} );
    }

    return !$error_code;
}

sub restart_attempt {
    my ( $self, $service, $attempt ) = @_;

    # common logic, when a service is started manually outside of systemd
    if ( $attempt == 1 && $service->doomed_rules() && scalar @{ $service->doomed_rules() } ) {
        $service->debug( q{The service '} . $service->service() . q{' failed to restart via systemd. The system will now kill all existing processes.} );
        Cpanel::RestartSrv::doomedprocess( $service->doomed_rules(), $service->verbose() );
    }

    return 1;
}

sub stop {
    my ( $self, $service, $type ) = @_;

    $type //= 'service';

    my $run = Cpanel::SafeRun::Object->new(
        'program' => $gl_systemctl_binary,
        'args'    => [ 'stop', $self->service() . ".$type" ]
    );
    my $error_code = $run->error_code();

    if ($error_code) {
        $service->debug( q{The system could not use the systemd daemon to stop the '} . $self->service() . qq{' $type: $error_code} );
    }
    else {
        $service->debug( q{The system successfully used systemd to stop the '} . $self->service() . qq{' $type.} );
    }

    return !$error_code;
}

sub status_helper {
    my ( $self, $service ) = @_;

    my $pidfile = $service->pidfile();

    # systemd oneshot services will not have a good list of pids, logic in check_service can handle this #
    my $info = $self->service_via_systemd();
    if ( $info && $info->{'Type'} && $info->{'Type'} eq 'oneshot' ) {
        return Cpanel::RestartSrv::check_service( 'service' => $service->service_name(), 'user' => $service->processowner(), 'pidfile' => $pidfile );
    }

    # abort when we detect the service inactive [can also probably only check this status]
    return unless $self->is_active($service);

    # Exim.. is kind of a 'special service' as when using /etc/exim_outgoing.conf
    #   we are expecting to check two PIDs...
    # This will likely require splitting the second daemon into its own systemd service.
    # case CPANEL-31360

    # check only the main pid, we can trust systemd
    if ( $service->has_single_pid() ) {
        if ( my $pid = Cpanel::RestartSrv::Systemd::get_pid_via_systemd( $self->service() ) ) {

            # MainPID can be equal to 0 when systemctl has no idea
            return Cpanel::RestartSrv::check_service(
                'service'      => $service->service_name(),    #
                'user'         => $service->processowner(),    #
                'pid'          => $pid,                        #
                'check_method' => 'systemd'                    #
            );
        }

        # when a service is 'active' with MainPID=0 then fallback to the legacy status check...
    }

    # systemctl is not aware of a 'MainPID' let's try to find one the old way...
    # legacy behavior
    # get a list of running pids #
    my @pids = Cpanel::RestartSrv::Systemd::get_pids_via_systemd( $self->service() );

    # and now get info for each one #
    my $out = '';
    foreach my $pid (@pids) {
        my $check = Cpanel::RestartSrv::check_service( 'service' => $service->service_name(), 'user' => $service->processowner(), 'pid' => $pid, 'check_method' => 'systemd' );
        $out .= $check if $check;
    }
    return $out;
}

sub is_active {
    my ( $self, $service ) = @_;

    my $info        = $self->service_via_systemd();
    my $activestate = $info->{'ActiveState'} // '';
    my $was_active  = $activestate eq 'active';

    my $service_name = $self->service();
    my $active       = _systemctl_is_active($service_name);

    if ( $was_active xor $active ) {

        # A "bounce" is detected. The active state now does not match what was
        # gathered a moment ago from systemd. Check the active state over a
        # short period of time to see if the service fails quickly due to a
        # recurring problem.
        for ( 1 .. 2 ) {
            sleep 1;
            $active = _systemctl_is_active($service_name);
            unless ($active) {
                $service->debug(qq{The service '$service_name' did not remain active for a short period. This may be caused by immediate service failure after startup.});
                last;
            }
        }
    }

    if ($active) {
        $service->debug(qq{The service '$service_name' is currently active.});
    }
    else {
        $service->debug(qq{The service '$service_name' is currently not active.});
    }

    return $active;
}

sub _systemctl_is_active {
    my ($service_name) = @_;
    my $run = Cpanel::SafeRun::Object->new(
        'program' => $gl_systemctl_binary,
        'args'    => [ '--quiet', 'is-active', $service_name . '.service' ]
    );
    my $error_code = $run->error_code();
    return !$error_code;
}

1;
