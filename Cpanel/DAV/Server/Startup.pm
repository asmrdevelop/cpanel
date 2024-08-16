package Cpanel::DAV::Server::Startup;

# cpanel - Cpanel/DAV/Server/Startup.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DAV::Server::Startup

=head1 SYNOPSIS

    my @handles = Cpanel::DAV::Server::Startup::open_ports(
        \@ports,
        $listenfds,
    );

=head1 DESCRIPTION

This contains the part of cpdavd’s startup that opens ports or
takes them in via the daemon’s C<--listenfds> parameter.

=cut

#----------------------------------------------------------------------

use Cpanel::Socket::Constants ();
use Cpanel::Socket::Micro     ();
use Cpanel::WebService        ();

use IO::Socket::INET  ();
use IO::Socket::INET6 ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 @handles = open_ports( \@PORTS, $LISTENFDS_ARG )

Opens the relevant ports for cpdavd.

Inputs are:

=over

=item * an arrayref of the port numbers that cpdavd needs (e.g., 2080)
(Can be gotten from L<Cpanel::DAV::Ports>.)

=item * the C<--listenfds> argument given to cpdavd (comma-separated
file descriptors), if any

=back

Returns a list of array references, each of which represents
a socket:

=over

=item * the socket’s file descriptor

=item * the Perl socket filehandle (an instance of either
L<IO::Socket::INET> or L<IO::Socket::INET6>)

B<NOTE:> As of this writing, C<sockport()> seems not to work with
L<IO::Socket::INET6> instances; it tries to parse the sockaddr as
IPv4, which obviously doesn’t work very well. As a result, we also
return …

=item * the socket’s bound port number (e.g., 2078)

=back

See L<Cpanel::Server::Listenfds> for a cpsrvd equivalent.

=cut

sub open_ports ( $ports_ar, $listenfds ) {
    my %needed_port_lookup;
    @needed_port_lookup{@$ports_ar} = ();

    my @handles;

    if ($listenfds) {

        local $^F = 1000;    #prevent cloexec

        foreach my $listenfd ( split( /,/, $listenfds ) ) {
            my $srvsocket;
            open( $srvsocket, '+<&=', $listenfd ) || die "Could not open fd $listenfd: $!";

            my $sockname = getsockname($srvsocket) or do {
                warn "Failed to getsockname(FD $listenfd): $!\n";
                next;
            };

            my ( $socktype, $port ) = Cpanel::Socket::Micro::unpack_sockaddr_of_any_type($sockname);
            if ( $socktype != $Cpanel::Socket::Constants::AF_INET && $socktype != $Cpanel::Socket::Constants::AF_INET6 ) {
                warn "Received non-IP socket (FD $listenfd, type $socktype). Skipping …\n";
                next;
            }

            if ( !exists $needed_port_lookup{$port} ) {
                warn "Received socket (FD $listenfd) for unrelated port $port. Ignoring …\n";
                next;
            }

            delete $needed_port_lookup{$port};

            bless $srvsocket, ( $socktype == $Cpanel::Socket::Constants::AF_INET6 ? 'IO::Socket::INET6' : 'IO::Socket::INET' );

            push @handles, [ fileno($srvsocket), $srvsocket, $port ];
        }
    }

    # Generally speaking, at this point %needed_port_lookup will either be:
    #   - empty, if $listenfds, or
    #   - full
    #
    # It’s possible, though, that we changed server profiles, so $listenfds
    # may not have contained FDs for all of the needed sockets. So let’s
    # ensure that we have everything before we proceed.
    #
    foreach my $port ( keys %needed_port_lookup ) {
        my $srvsockets = Cpanel::WebService::setupservice($port);
        foreach my $srvsocket ( @{$srvsockets} ) {
            push @handles, [ fileno($srvsocket), $srvsocket, $port ];
        }
    }

    return @handles;
}

1;
