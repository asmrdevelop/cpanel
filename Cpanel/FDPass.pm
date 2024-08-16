package Cpanel::FDPass;

# cpanel - Cpanel/FDPass.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 DESCRIPTION

A thin wrapper around L<IO::FDPass> so we give and receive handles,
not file descriptors.

=cut

#----------------------------------------------------------------------

use IO::FDPass ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 send( $SOCKET, $PASSED_FH )

Just like C<IO::FDPass::send()> but accepts Perl filehandles
rather than file descriptors.

Note also that this function’s tests guarantee that the payload it
sends across the socket is a single NUL byte. (This comes from L<IO::FDPass>
underneath, but it’s not documented there.) So if you use this module
you can reliably check for that NUL (e.g., with C<recv( .., MSG_PEEK )>)
to determine if there might be a filehandle waiting for you.

=cut

sub send {
    my ( $socket, $passee ) = @_;

    return IO::FDPass::send( _to_fd( $socket, $passee ) );
}

=head2 $FILEHANDLE = send( $SOCKET )

Just like C<IO::FDPass::recv()> but accepts and returns Perl filehandles
rather than file descriptors, and if there is no file descriptor received
this returns undef instead of -1.

=cut

sub recv {
    my ($socket) = @_;

    my $fd = IO::FDPass::recv( _to_fd($socket) );

    if ( $fd > -1 ) {
        return _fd_to_fh($fd);
    }

    return undef;
}

sub _fd_to_fh {
    my ($fd) = @_;

    # Perl doesn’t seem to care about a filehandle’s access mode here,
    # but let’s just treat them all as read/write to be safe.
    open my $fh, '+<&=', $fd or die "open(+<&=): $!";

    return $fh;
}

sub _to_fd {
    $_ = ref() ? fileno($_) : $_ for @_;
    return @_;
}

1;
