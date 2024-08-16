package Cpanel::TCP::Close;

# cpanel - Cpanel/TCP/Close.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::TCP::Close - RST-safe TCP close

=head1 SYNOPSIS

    Cpanel::TCP::Close::close_avoid_rst($socket);

=head1 DESCRIPTION

The BSD sockets API is a thing of beauty: we can interact with sockets
the same way we do with pipes/ptys/etc., and for the most part, it all
“just works”.

C<close()>ing a TCP socket is one of the leaks in that abstraction. This
module helps with that.

=head1 WHY IS THIS IMPORTANT?

Usually when you tell Linux to C<close()> a socket, the kernel sends a
FIN packet to the peer to close the connection. If, though, that socket’s
read buffer is non-empty, the kernel interprets this as a premature
termination, which is a failure state. In response, the kernel sends RST,
not FIN, to the peer.

This is particularly awful because it will actually preempt any data that
was already sent to the peer and prevent that peer from reading further.

The solution is to clear out the socket’s read buffer prior to C<close()>,
which is what this module implements.

Example: Your HTTP server receives a POST to a nonexistent URL. The request
is 10 KiB in size, but you only read the first 100 bytes to get the URL.
The URL is to an unknown resource, so you’ll send an HTTP 404 response and
ignore the rest of the request. B<BUT>, if you don’t clear out that read
buffer, the client may never receive your 404 response because its read
operation will give an ECONNRESET error instead.

(The client may receive EPIPE/SIGPIPE if it naïvely tries to send its full
request before reading the response, but that’s its problem.)

=head1 WHEN TO USE THIS MODULE

Use this module whenever you want to avoid the potential RST problem
described above. There may not be any time when you I<don’t> want that,
in which case you could use this module to close any TCP socket.

=head1 PEEKING AT A SOCKET’S READ BUFFER

If, for some reason, you want to look at the read buffer size I<before>
you close the socket, you can use L<ioctl(2)>, thus:

    use constant FIONREAD => 0x541b;

    ioctl( $socket, FIONREAD, my $pending = q<> ) or die "ioctl(): $1";
    $pending = unpack 'I', $pending;

This may not always be reliable down to the last byte.

=cut

#----------------------------------------------------------------------

use constant _SHUT_RD => 0;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $close_result = close_avoid_rst( $SOCKET )

This ensures that $SOCKET’s read buffer is empty before C<close()>ing it.

This returns the value from the underlying call to Perl’s C<close()>
built-in. C<$!> is set as you’d expect.

Behavior is undefined if $SOCKET is a non-TCP-socket file descriptor.

=cut

sub close_avoid_rst ($socket) {
    my $fd = fileno $socket // do {
        return;
    };

    # NB: There’s little point in warn()ing here; the only likely
    # error is ENOTCONN, which can happen in normal operation if
    # the client already closed the connection, but we already
    # checked for that above.
    shutdown( $socket, _SHUT_RD );

    # read()ing from the socket is a more reliable indicator of when
    # it’s empty than using ioctl() beforehand to discern the number of
    # read-pending bytes.
    1 while sysread( $socket, my $buf, 65536 );

    return close $socket;
}

1;
