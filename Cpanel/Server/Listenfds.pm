package Cpanel::Server::Listenfds;

# cpanel - Cpanel/Server/Listenfds.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Listenfds

=head1 SYNOPSIS

    my $parsed_ar = Cpanel::Server::Listenfds::parse( $listenfds_str );

=head1 DESCRIPTION

This module parses the C<--listen> argument given to either cpsrvd or
cpsrvd-dormant.

=cut

#----------------------------------------------------------------------

use Cpanel::Socket::Constants ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $parsed_ar = parse( $LISTENFDS_STR )

$LISTENFDS_STR is a comma-joined list of file descriptors.

The return is an arrayref, each of whose elements is an arrayref of:

=over

=item * The file descriptor (same number as passed in)

=item * A Perl filehandle (unblessed!) to that file descriptor.
You can C<bless()> this into the relevant L<IO::Socket> subclass
as needed.

=item * The socket’s family number (e.g., C<Socket::AF_UNIX()>)

=item * Either the socket’s port number (AF_INET and AF_INET6 sockets)
or its filesystem path (AF_UNIX sockets).

=back

Any file descriptor numbers that are not sockets or are not open file
descriptors will prompt an appropriate warning and will be omitted from
the returned data structure.

See L<Cpanel::DAV::Server::Startup> for a cpdavd equivalent.

=cut

sub parse {
    my ($listenfds_str) = @_;

    my @return;

    local $^F = 1000;    #prevent cloexec

    for my $listenfd ( split( /,/, $listenfds_str ) ) {
        my $srvsocket;
        open( $srvsocket, '+<&=', $listenfd ) or do {
            warn "==> XXX open FD $listenfd: $!\n";
            next;
        };

        my $sockname = getsockname($srvsocket) // do {
            warn "==> XXX getsockname() on FD $listenfd failed: $!\n";
            next;
        };

        my ( $sock_type, $sockport ) = unpack 'Sn', $sockname;

        if ( $sock_type == $Cpanel::Socket::Constants::AF_UNIX ) {
            $sockport = ( unpack 'vZ*', $sockname )[1];
        }

        push @return, [ $listenfd, $srvsocket, $sock_type, $sockport ];
    }

    return \@return;
}

1;
