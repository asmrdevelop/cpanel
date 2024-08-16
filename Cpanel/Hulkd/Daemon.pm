package Cpanel::Hulkd::Daemon;

# cpanel - Cpanel/Hulkd/Daemon.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Hulkd::Proc ();
use Cpanel::Proc::PID   ();

use constant _ENOENT => 2;

our $PID_DIR  = '/var/run';
our $PID_FILE = "$PID_DIR/cphulkd_dbprocessor.pid";

=encoding utf-8

=head1 NAME

Cpanel::Hulkd::Daemon

=head1 SYNOPSIS

use Cpanel::Hulkd::Daemon ();

my $call_on_daemons_cr = sub {
    # $app currently is only 'processor' see Cpanel::Hulkd::Proc::get_applist_ref()
    my ( $app, $pidfile, $pid_from_pidfile ) = @_;
    ...
};

Cpanel::Hulkd::exec_on_hulk_daemons($call_on_daemons_cr);

=head1 DESCRIPTION

This module is a collection of utility functions to act and acting on running (or previously running) hulk services.

=head1 FUNCTIONS

=head2 stop_daemons()

This function calls Cpanel::Kill::Single::safekill_single_pid on each of the hulkd processes
that have defined pidfiles.

=head3 Arguments

None.

=head3 Returns

This function returns what exec_on_hulk_daemons returns, which is currently 1.

=head3 Exceptions

None.

=cut

sub stop_daemons {
    return exec_on_hulk_daemons(
        sub {
            my ( $app, $pidfile, $previous_pid ) = @_;
            require Cpanel::Kill::Single;
            Cpanel::Kill::Single::safekill_single_pid($previous_pid);
            unlink $pidfile;
        }
    );
}

=head2 reload_daemons()

This function sends the 'HUP' signal to each of the hulkd processes
that defined a pidfile.

=head3 Arguments

None.

=head3 Returns

This function returns the sum of the return of sending the 'HUP' signal. Thereby,
returning 1 for each process that was successfully signaled.

=head3 Exceptions

None.

=cut

sub reload_daemons {
    my $killed = 0;
    exec_on_hulk_daemons(
        sub {
            my ( $app, $pidfile, $previous_pid ) = @_;
            $killed += kill( 'HUP', $previous_pid );
        }
    );
    return $killed;
}

=head2 exec_on_hulk_daemons( CODEREF )

This function accepts a coderef that will be run on each hulk daemon that
defined a pidfile. The coderef will receive the following arguments:

=head3 Arguments

=over 4

=item coderef - CODEREF - This argument should be a coderef that will be run on each of the hulk daemons that defined a pidfile.
                            See above for inputs to this coderef.

=back

=head4 CODEREF Arguments

=over 4

=item app    - SCALAR - The app name of the hulk daemon. See Cpanel::Hulkd::Proc::get_applist_ref for the list of apps

=item pidfile    - SCALAR - The path to the pidfile defined by the hulk daemon

=item pid_from_pidfile - SCALAR - The pid defined in the pidfile for the daemon.

=back

=head3 Returns

This function currently always returns 1.

=head3 Exceptions

None.

=cut

sub exec_on_hulk_daemons {
    my ($coderef) = @_;

    my @apps = Cpanel::Hulkd::Proc::get_applist();

    foreach my $app (@apps) {
        my $pidfile = "$PID_DIR/cphulkd_${app}.pid";
        if ( -e $pidfile ) {
            require Cpanel::ProcessCheck::Running;
            if ( open my $pid_fh, '<', $pidfile ) {
                my $previous_pid;
                chomp( $previous_pid = readline($pid_fh) );
                close $pid_fh;

                local $@;
                eval {
                    my $pid_check = Cpanel::ProcessCheck::Running->new( pid => $previous_pid, user => 0, pattern => 'hulk' );
                    $pid_check->check_all();
                };

                $coderef->( $app, $pidfile, $previous_pid ) if $previous_pid && !$@;
            }
        }
    }
    return 1;
}

=head2 shutdown_db_proc()

This will shutdown the dbprocessor daemon if it is running.

=head3 Arguments

None.

=head3 Returns

Returns 1 if a pid was killed.
If it was unable to find a pid, it returns 0.

=head3 Exceptions

None.

=cut

sub shutdown_db_proc {

    my $pid = get_db_proc_pid();

    if ($pid) {
        require Cpanel::Kill::Single;
        Cpanel::Kill::Single::safekill_single_pid($pid);
        unlink $PID_FILE;
        return 1;
    }

    return 0;
}

=head2 get_db_proc_pid()

This will get the pid of the dbprocessor from its pidfile,
then check that the pid is a currently running process.

=head3 Arguments

None.

=head3 Returns

Returns the dbprocessor pid if the pid in the $PID_FILE is running
and not a zombie.

Otherwise returns 0.

=head3 Exceptions

None.

=cut

sub get_db_proc_pid {
    if ( open my $pid_fh, '<', $PID_FILE ) {
        my $pid;
        chomp( $pid = readline($pid_fh) );
        close $pid_fh;

        my $pid_to_return;

        local $@;

        eval {
            my $proc_obj = Cpanel::Proc::PID->new($pid);
            my $cmdline  = join( ' ', @{ $proc_obj->cmdline() } );
            my $state    = $proc_obj->state();

            if ( index( $cmdline, 'cPhulkd - dbprocessor' ) > -1 && $state ne 'Z' ) {
                $pid_to_return = $pid;
            }
        };

        return $pid_to_return if $pid_to_return;

        if ( my $err = $@ ) {
            if ( !eval { $err->isa('Cpanel::Exception::ProcessNotRunning') } ) {
                local $@ = $err;
                warn;
            }
        }
    }
    elsif ( $! != _ENOENT() ) {
        warn "open($PID_FILE): $!";
    }

    return 0;
}

1;
