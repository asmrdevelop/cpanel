package Cpanel::Kill::AppPort;

# cpanel - Cpanel/Kill/AppPort.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Kill::AppPort - Terminate applications that are listening on port or unix sockets

=head1 SYNOPSIS

    use Cpanel::Kill::AppPort;

    Cpanel::Kill::AppPort::kill_apps_on_ports(
        'socks_and_ports' => [579,'/var/run/my.sock'],
        'verbose' => $Cpanel::Kill::AppPort::VERBOSE,
        'timeout' => 666,
        'exclude_ips' => [ '1.2.3.4', '5.6.7.8' ],
    );

=cut

use Cpanel::AppPort     ();
use Cpanel::Kill        ();
use Cpanel::ProcessInfo ();

our $DEFAULT_TIMEOUT = 6;
our $VERBOSE         = 1;

=head2 kill_apps_on_ports($port_and_socket_list_ar, $verbose, $timeout)

Use Cpanel::Kill::safekill_multipid to terminate applications
that are listening on the specified ports and unix sockets.  It will avoid
terminating the current process and any processes that are ancestor of the
current process.

=over 2

=item Input

=over 3

=item $opts C<HASH>

    A hash consisting of one or more of the following options:

=over 3

=item ports_and_sockets C<ARRAYREF>

    An arrayref of port numbers and unix socket paths.

=item verbose C<SCALAR>

    If true, print verbose details on the termination process

=item timeout C<SCALAR>

    If a process does not die after SIGTERM, SIGKILL will
    be sent after the timeout.

=item exclude_ips C<ARRAYREF>

    An arrayref of IPs to exclude from the list of pids to kill

=back

=back

=back

=cut

sub kill_apps_on_ports {
    my %opts = @_;

    $opts{'ports'} || die 'Ports array reference is required';
    $opts{'verbose'}     //= 0;
    $opts{'timeout'}     //= $DEFAULT_TIMEOUT;
    $opts{'exclude_ips'} //= [];

    # Don’t kill() ancestor processes of the current process.
    my %protected_pids = map { $_ => 1 } ( Cpanel::ProcessInfo::get_pid_lineage(), $$ );

    my $app_pid_ref = Cpanel::AppPort::get_pids_bound_to_ports( $opts{'ports'} );
    if ( ref $app_pid_ref ) {
        my @pids;
        foreach my $pid ( keys %{$app_pid_ref} ) {
            next if $protected_pids{$pid};

            my ( $process, $owner, $address ) = @{ $app_pid_ref->{$pid} }{ 'process', 'owner', 'address' };

            if ( scalar @{ $opts{'exclude_ips'} } > 0 ) {
                if ( grep { $_ eq $address } @{ $opts{'exclude_ips'} } ) {
                    print "Ignoring $address...\n" if $opts{'verbose'};
                    next;
                }
            }

            if ( $opts{'verbose'} ) {
                my $how = ( $opts{'timeout'} == 0 ? 'Forcefully' : 'Gracefully' );
                print "$how terminating process: $process with pid $pid and owner $owner.\n";
            }

            push @pids, $pid;
        }
        if (@pids) {
            if ( $opts{'timeout'} == 0 ) {
                _force_kill(@pids);
            }
            else {
                Cpanel::Kill::safekill_multipid( \@pids, $opts{'verbose'}, $opts{'timeout'} );
            }
        }
    }
    return;
}

sub _force_kill {
    my (@pids) = @_;

    return kill( 'KILL', @pids );
}

1;
