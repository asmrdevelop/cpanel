package Cpanel::ServiceManager::Hot;

# cpanel - Cpanel/ServiceManager/Hot.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 MODULE

=head2 NAME

Cpanel::ServiceManager::Hot

=head2 DESCRIPTION

This is the parent class for Cpanel::ServiceManager::Services that support hot restarts

=cut

use strict;
use warnings;

use Moo;
use Cpanel::ServiceManager::Base ();
use Try::Tiny;

extends 'Cpanel::ServiceManager::Base';

has 'is_graceful_restart_enabled' => ( is => 'rw', 'default' => 1 );

=head2 restart_gracefully

Implements hot restarts will fallback to a full restart if it fails
for services like cpsrvd and dnsadmin which support a hot restart by getting USR1

All services that support hot restarts must use

use Cpanel::Services::Hot ();

and

Cpanel::Services::Hot::make_pid_file($pid_file);

to ensure find_outdated_services does not generate false positives

=cut

sub restart_gracefully {
    my $self = shift;

    if ( !$self->is_graceful_restart_enabled() ) {
        $self->debug("Soft restart is disabled");
        return 0;
    }

    my $pidfile = $self->pidfile();

    # Can't signal the process if no pid file
    return 0 if !-e $pidfile || -z _;
    my $pidfile_timestamp_before_sending_signal = ( stat(_) )[9];

    if ( $pidfile_timestamp_before_sending_signal == time() ) {

        # If we are doing two hot restarts in the same second we need to
        # reset the timestamp on the pidfile 1 second in the past
        # so we can check to see if it ages
        my $one_second_ago = time() - 1;
        utime $one_second_ago, $one_second_ago, $pidfile;
        $pidfile_timestamp_before_sending_signal = $one_second_ago;
    }

    # Read in the pid.
    my $pid = $self->_read_pid_from_pidfile();
    return 0 if !$pid;

    my ( $inotify_obj, $rin );

    #We don’t care about failures because this just means
    #it will be slower
    try {
        require Cpanel::Inotify;
        $inotify_obj = Cpanel::Inotify->new( flags => ['NONBLOCK'] );
        $inotify_obj->add( $pidfile, flags => [ 'ATTRIB', 'DELETE_SELF', 'MODIFY' ] );
        vec( $rin, $inotify_obj->fileno(), 1 ) = 1;
    }
    catch {
        local $@ = $_;
        warn;
    };

    # XXXX-dormant knows how to handle USR1 and reexec()
    # Fail if the proc couldn't be signaled.
    return 0 if !$self->_send_usr1($pid);

    my $service_name = $self->service_name();

    # Watch for the pid file to change time stamp.
    foreach my $count ( 1 .. 600 ) {

        $self->output_partial('…')
          if 1 == $self->verbose();

        my $rout = undef;

        # give service time to bounce and not be pegged #
        select( $rout = $rin, undef, undef, 0.025 );

        my @stat_info = stat($pidfile);
        if ( -e _ && !-z _ ) {
            if ( $stat_info[9] && $stat_info[9] != $pidfile_timestamp_before_sending_signal ) {
                print "The system accepted the USR1 value.\n" if 2 == $self->verbose();
                return 1;
            }
        }
        if ( $count == 1 && 2 == $self->verbose() ) {
            print "The system is waiting for the $service_name service to restart.\n";
        }
    }

    print "The system failed to restart the $service_name service gracefully, and will now perform a forced restart.\n"
      if $self->verbose();
    return 0;
}

sub _read_pid_from_pidfile {
    my ($self) = @_;

    open( my $fh, '<', $self->pidfile() ) or return;
    my $pid = <$fh>;
    chomp $pid;

    return $pid;
}

sub _send_usr1 {    # mocked in tests
    my ( $self, $pid ) = @_;

    return kill( 'USR1', $pid );
}

1;
