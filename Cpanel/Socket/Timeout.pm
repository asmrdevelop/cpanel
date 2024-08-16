package Cpanel::Socket::Timeout;

# cpanel - Cpanel/Socket/Timeout.pm                  Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Struct::timeval ();

=encoding utf-8

=head1 NAME

Cpanel::Socket::Timeout - timeouts for blocking socket operations

=head1 SYNOPSIS

    {
        my $rtimeout = Cpanel::Socket::Timeout::create_read( $socket, 5.2 );

        # Will time out after 5.2 seconds
        sysread( $socket, my $buf, 1 );
    }

    # Will block for however long the previous timeout setting was.
    # (Default is to block forever.)
    sysread( $socket, my $buf, 1 );

=head1 DESCRIPTION

Linux provides the C<SO_RCVTIMEO> and C<SO_SNDTIMEO> constants for
making read and write operations on blocking sockets time out after
a certain length of time. (See L<socket(7)> for more details.)

This is a much simpler way to get a timeout on a blocking I/O operation
than to use non-blocking I/O. It’s also safer than C<alarm()> because you
avoid potential interference with a previously set alarm.

Note also that this applies to all I/O operations
on the socket, including C<connect()> (write) and C<accept()> (read).

=head1 AUTOMATIC CLEANUP

You could just call C<setsockopt()> directly to set your timeout, but
that will affect the socket’s global state, which can yield nasty
action-at-a-distance bugs. This module avoids that by always creating
an object that, on DESTROY, resets the timeout to its state from immediately
before the timeout was set.

=cut

use constant {
    _EBADF => 9,

    # Copied from Socket.pm:
    _SOL_SOCKET  => 1,
    _SO_RCVTIMEO => 20,
    _SO_SNDTIMEO => 21,
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $obj = create_read( $SOCKET, $TIMEOUT )

Sets $SOCKET’s read timeout to $TIMEOUT seconds and returns an
object that, when DESTROYed, resets the timeout to its previous
value. C<die()>s if called in void context.

=cut

sub create_read {
    return _create( 'SO_RCVTIMEO', @_ );
}

#----------------------------------------------------------------------

=head2 $obj = create_write( $SOCKET, $TIMEOUT )

Same as C<create_read()> but for $SOCKET’s write timeout.

=cut

sub create_write {
    return _create( 'SO_SNDTIMEO', @_ );
}

#----------------------------------------------------------------------

sub _create {
    my ( $which, $socket, $secs ) = @_;

    die 'Void context is useless!' if !defined wantarray;

    my $whichnum = __PACKAGE__->can("_$which")->();

    local $!;

    my $before = getsockopt( $socket, _SOL_SOCKET(), $whichnum ) or do {
        die "Failed to read $which from $socket: $!";
    };

    setsockopt(
        $socket,
        _SOL_SOCKET(), $whichnum,
        Cpanel::Struct::timeval->float_to_binary($secs),
      )
      or do {
        die "Failed to set $which on $socket to $secs: $!";
      };

    return bless [ $socket, $which, $before ] => __PACKAGE__;
}

sub DESTROY {
    my ($self) = @_;

    my $whichnum = __PACKAGE__->can("_$self->[1]")->();

    # Don’t bother restoring the socket state if the socket is
    # already closed.
    if ( fileno $self->[0] ) {
        setsockopt( $self->[0], _SOL_SOCKET(), $whichnum, $self->[2] ) or do {

            # EBADF probably just means that Perl thinks the socket is open
            # after the kernel has already closed it. This isn’t worth
            # making noise over, so we ignore it.
            if ( $! != _EBADF() ) {

                # Based on setsockopt(2) it seems very unlikely
                # that we’d ever get here. But let’s handle it anyway.
                my $secs = Cpanel::Struct::timeval->binary_to_float( $self->[2] );
                die "Failed to reset $self->[1] on $self->[0] to $secs: $!";
            }
        };
    }

    return;
}

1;
