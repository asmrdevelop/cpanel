package Cpanel::AppPort;

# cpanel - Cpanel/AppPort.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Lsof     ();
use Cpanel::Slurper  ();
use Cpanel::PwCache  ();
use Cpanel::Sys::Net ();

sub get_pids_bound_to_ports ($port_ref) {
    my $tcp_ports_open = Cpanel::Sys::Net::get_tcp4_sockets();

    # We need to split out files from open ports to check.
    my ( @open_ports, @open_files );
    foreach my $socket (@$port_ref) {
        if ( $socket =~ m/^[0-9]+$/ ) {
            push @open_ports, $socket;
        }
        else {
            push @open_files, $socket;
        }
    }

    # Figure out which inodes we need to check if any.
    my @inodes_to_check;
    foreach my $socket (@$tcp_ports_open) {
        my $sport = $socket->{'sport'} or next;
        next unless grep { length $_ && $sport == $_ } @open_ports;

        $socket->{'src'} = '*' if $socket->{'src'} eq '0.0.0.0';
        push @inodes_to_check, { inode => $socket->{'inode'}, address => $socket->{'src'} };
    }

    return {} unless @inodes_to_check || @open_files;

    # Which pids are we going to report on based on open inodes in /proc/XX/fd
    my %PIDLIST;

    # Check if any open files match the socket inodes we want.
    Cpanel::Lsof::clear_cache();
    foreach my $socket (@inodes_to_check) {
        next unless length $socket->{'inode'};
        foreach my $pid ( Cpanel::Lsof::get_pids_using_socket_inode( $socket->{'inode'} ) ) {
            $PIDLIST{$pid} //= {};
            $PIDLIST{$pid}->{'address'} //= $socket->{'address'};
            $PIDLIST{$pid}->{'address'} = '*' if $socket->{'address'} eq '*';    # * always clobbers individual listens.
        }
    }

    # Look if any pids have the files we're checking for open.
    foreach my $socket_file (@open_files) {
        foreach my $pid ( Cpanel::Lsof::get_pids_using_file($socket_file) ) {
            $PIDLIST{$pid} //= {};
            $PIDLIST{$pid}->{'address'} //= $socket_file;
        }
    }

    return {} unless %PIDLIST;    # No sockets could be found attached to these???

    # Provide additional information on the pids we have identified.
    foreach my $pid ( keys %PIDLIST ) {
        my $cmdline = eval { Cpanel::Slurper::read("/proc/$pid/cmdline") } // '';
        $cmdline =~ s/\0.*$//;    # Strip everything after null byte.
        $cmdline =~ s/ +$//;      # Strip white space.
        $PIDLIST{$pid}->{'process'} = $cmdline;

        my @stat = lstat "/proc/$pid";
        if ( !@stat ) {           # The pid probably went away so let's just remove it from the list.
            delete $PIDLIST{$pid};
            next;
        }

        my $id = $stat[4];
        $PIDLIST{$pid}->{'owner'} = ( Cpanel::PwCache::getpwuid_noshadow($id) )[0] // $id;

    }

    return \%PIDLIST;
}

1;
