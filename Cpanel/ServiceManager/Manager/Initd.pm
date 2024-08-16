package Cpanel::ServiceManager::Manager::Initd;

# cpanel - Cpanel/ServiceManager/Manager/Initd.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 MODULE

=head2 NAME

Cpanel::ServiceManager::Manager::Initd

=head2 DESCRIPTION

Methods for dealing with Sys-V/initd based systems.

=cut

use strict;
use warnings;

use Moo;

use Cpanel::Env             ();
use Cpanel::RestartSrv      ();
use Cpanel::FileUtils::Link ();
use Cpanel::TimeHiRes       ();
use Cpanel::LoadModule      ();

has 'service'          => ( is => 'rw', lazy    => 1 );
has 'init_script'      => ( is => 'rw', lazy    => 1, default => sub { return Cpanel::RestartSrv::getinitfile( $_[0]->service() ); } );
has 'wipe_startup_log' => ( is => 'rw', default => 1 );

# If this_process_was_executed_by_systemd is 1 this means that we were called by
# systemd so we are falling back to the init.d code
#
# The most common example of this is when
# ExecStop=/scripts/restartsrv_tailwatchd --stop
# or
# ExecStart=/scripts/restartsrv_tailwatchd --start
#
# In this case we need to take care of starting
# or stopping the process ourselves.  Since the
# Systemd.pm module calls systemd to to this
#
# restartsrv_base will set this flag and use and
# we will end up here.
has 'this_process_was_executed_by_systemd' => ( is => 'rw', lazy => 1, default => 0 );

sub start {
    my ( $self, $service ) = @_;

    $service->debug( 'The system is using the Initd method to start the ' . $self->service() . ' service.' );

    # figure out whether we have a cpanel service, init script we can call directly (which may not be in /etc/init.d) or invoke the service directly #
    my $ec;
    my @called;
    if ( $service->is_cpanel_service() ) {
        $service->debug( q{The system will use the service's binary to start the '} . $self->service() . q{' service.} )
          if !$ec;

        # do this just in case there's a dead pid file #
        unlink $service->pidfile() if $service->pidfile() && -f $service->pidfile();
        Cpanel::Env::set_safe_path();
        @called = ( $service->service_binary(), @{ $service->startup_args() || [] } );
        if ( Cpanel::RestartSrv::logged_startup( $service->service_name(), $self->wipe_startup_log(), [ $service->service_binary(), @{ $service->startup_args() || [] } ], 'wait' => 1 ) ) {
            $ec = $?;
        }
        $service->debug( q{The system successfully used the service binary to start the service '} . $self->service() . q{'.} )
          if !$ec;
    }
    elsif ( $self->init_script() ) {
        $service->debug( q{The system will use the init.d script, } . $self->init_script() . q{, to start the '} . $self->service() . q{' service.} );

        @called = ( $self->init_script(), 'start' );
        if ( Cpanel::RestartSrv::logged_startup( $service->service_name(), $self->wipe_startup_log(), [ $self->init_script(), 'start' ], 'wait' => 1 ) ) {
            $ec = $?;
        }

        $service->debug( q{The system successfully used the init.d script to start the service '} . $self->service() . q{'.} )
          if !$ec;
    }
    else {

        # TODO: ALL SERVICES SHOULD HAVE INIT SCRIPTS #
        $service->debug( 'The system is falling back to manually starting the ' . $self->service() . ' service.' );

        @called = ( $service->service_binary(), @{ $service->startup_args() || [] } );
        if ( Cpanel::RestartSrv::logged_startup( $service->service_name(), $self->wipe_startup_log(), [ $service->service_binary(), @{ $service->startup_args() || [] } ], 'wait' => 1 ) ) {
            $ec = $?;
        }
        $service->debug( q{The system successfully used the service binary to start the service '} . $self->service() . q{'.} )
          if !$ec;
    }

    if ($ec) {
        Cpanel::LoadModule::load_perl_module('Cpanel::ChildErrorStringifier');
        my $why          = Cpanel::ChildErrorStringifier->new($ec)->autopsy();
        my $service_name = $service->service();
        $service->warn( "The system encountered an error while starting the “$service_name” service with the command “" . join( ' ', @called ) . "”: $why" );
    }

    return !$ec;
}

sub restart {
    my ( $self, $service ) = @_;

    # figure out whether we have a cpanel service, init script we can call directly (which may not be in /etc/init.d) or invoke the service directly #
    my $ec;
    if ( $service->is_cpanel_service() ) {

        # do this just in case there's a dead pid file #
        Cpanel::FileUtils::Link::safeunlink( $service->pidfile() ) if $service->pidfile() && -f $service->pidfile();
        Cpanel::Env::set_safe_path();
        if ( Cpanel::RestartSrv::logged_startup( $service->service_name(), $self->wipe_startup_log(), [ $service->service_binary(), @{ $service->restart_args() || [] } ], 'wait' => 1 ) ) {
            $ec = $?;
        }
        $service->debug( q{The system successfully used the service binary to restart the service '} . $self->service() . q{'.} )
          if !$ec;
    }
    elsif ( $self->init_script() ) {
        if ( Cpanel::RestartSrv::logged_startup( $service->service_name(), $self->wipe_startup_log(), [ $self->init_script(), 'start' ], 'wait' => 1 ) ) {
            $ec = $?;
        }
        $service->debug( q{The system successfully used the init.d script to restart the service '} . $self->service() . q{'.} )
          if !$ec;
    }
    else {
        # TODO: ALL SERVICES SHOULD HAVE INIT SCRIPTS #
        $service->warn( 'The system is manually starting the service: ' . $self->service() );
        if ( Cpanel::RestartSrv::logged_startup( $service->service_name(), $self->wipe_startup_log(), [ $service->service_binary(), @{ $service->restart_args() || [] } ], 'wait' => 1 ) ) {
            $ec = $?;
        }
        $service->debug( q{The system successfully used the service binary to restart the service '} . $self->service() . q{'.} )
          if !$ec;
    }
    return !$ec;
}

sub reload {
    my ( $self, $service ) = @_;

    my $ec;

    if ( $self->init_script() ) {
        if ( Cpanel::RestartSrv::logged_startup( $service->service_name(), $self->wipe_startup_log(), [ $self->init_script(), 'reload' ], 'wait' => 1 ) ) {
            $ec = $?;
        }
        $service->info( q{The system successfully used the init.d script to reload the service '} . $self->service() . q{'.} )
          if $service->verbose() && !$ec;
    }

    return !$ec;
}

sub stop {
    my ( $self, $service ) = @_;

    my $successes = 0;

    # figure out whether we have an init script we can call directly (which may not be in /etc/init.d) or we use the service command #
    if ( $service->is_cpanel_service() ) {
        Cpanel::Env::set_safe_path();
        if ( scalar @{ $service->shutdown_args() || [] } && Cpanel::RestartSrv::logged_startup( $service->service_name(), 0, [ $service->service_binary(), @{ $service->shutdown_args() } ], 'wait' => 1 ) && !$? ) {
            $service->debug( q{The system successfully used service binary stop arguments to stopthe service '} . $self->service() . q{'.} );
            $successes++;
        }
    }
    elsif ( $self->init_script() ) {
        if ( Cpanel::RestartSrv::logged_startup( $service->service_name(), 0, [ $self->init_script(), 'stop' ], 'wait' => 1 ) && !$? ) {
            $service->debug( q{The system successfully used the init.d script to stop the service '} . $self->service() . q{'.} );
            $successes++;
        }
    }

    my $handled_by_pid = 0;

    # if we have a pidfile, let's use it to kill the service #
    if ( $service->pidfile() && -e $service->pidfile() ) {

        # read in the pid #
        open( my $fh, '<', $service->pidfile() ) or die q{The system failed to read the service '} . $service->service() . q{' pidfile '} . $service->pidfile() . "': $!";
        my $pid = readline $fh;
        $pid and chomp $pid;
        $pid or goto stop_nokillpidfile;

        if ( $service->pid_exe() ) {

            # make sure this is the expected process #
            goto stop_nokillpidfile if !-d "/proc/$pid";
            my $exe = readlink("/proc/$pid/exe")
              or die q{The system failed to find the service '} . $service->service() . q{' pidfile '} . $service->pidfile() . "': $!";

            # CloudLinux prepends this, while CentOS and RHEL append it.
            $exe =~ s/^\(deleted\)\s+|\s+\(deleted\)$//;
            if ( $exe !~ $service->pid_exe() ) {
                warn q{The system did not expect the .exe file for the '} . $service->service() . q{' service's PID file '} . $service->pidfile() . "'. The system will not kill the PID: $exe";
                goto stop_nokillpidfile;
            }
        }

        # send kill the process #
        kill 'TERM', $pid;

        # now wait for it to die #
        my $die_timer = time();
        my $process_killed;
        my $first = 1;
        while ( time() - $die_timer <= 30 ) {
            if ( !-e "/proc/$pid" ) {
                $process_killed = 1;
                last;
            }
            if ($first) {
                $service->debug(qq{Waiting for PID $pid to finish...});
                $first = 0;
            }
            Cpanel::TimeHiRes::sleep(0.2);
        }

        if ($process_killed) {
            $service->debug( q{The system successfully used the PID file to stop the service '} . $self->service() . q{'.} );
            $handled_by_pid = 1;
            $successes++;
        }
      stop_nokillpidfile:
    }

    # We cannot avoid this doing this on systemd
    # systems as it will mean that we will always
    # fall through and kill every app that is on the apps
    # ports which could kill litespeed or litespeed cgi
    # unexpectedly.  It also means that for apps
    # like tailwatchd which never have a port binding
    # we will never kill off orphaned processes
    # and they just build up over time of the pid file
    # is ever lost.
    #
    # In case FB-185789 the behavior was changed to avoid
    # calling the doomed rules on systemd systems
    # however since we call the init.d code when
    # ExecStop=/scripts/restartsrv_XXXX --stop to
    # kill off the processes we must run the doomedprocess code
    # since we rely on the init.d code to kill the process
    #
    if ( !$handled_by_pid ) {

        # doooOooooom!!! #
        if ( scalar @{ $service->doomed_rules() || [] } ) {
            my $processowner = $service->processowner();

            # FIXME: doomedprocess calls Cpanel::Kill::safekill which doesn't actually return a status of any value #
            $service->debug(q{The system is cleaning up any leftover processes.});
            if (
                Cpanel::RestartSrv::doomedprocess(
                    $service->doomed_rules(),                             #rules
                    2 == $service->verbose(),                             #verbose
                    undef,                                                #wait time
                    ( $processowner ? { $processowner => 1 } : undef )    # allowed_owners
                )
            ) {
                $service->debug( q{All other attempts to stop the service have failed. The system successfully used an internal function to stop the service '} . $self->service() . q{'.} )
                  if !$successes;
                $successes++;
            }
        }
    }

    # now kill by ports if necessary #
    $successes++ if $service->kill_apps_on_ports();

    $service->info( q{The service '} . $self->service() . qq{' appears to be already down. Nothing was stopped.} )
      if !$successes;

    return 1;
}

1;
