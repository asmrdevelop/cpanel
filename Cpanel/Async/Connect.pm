package Cpanel::Async::Connect;

# cpanel - Cpanel/Async/Connect.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::Connect - Convenient asynchronous C<connect()>

=head1 SYNOPSIS

    use Socket;

    my $connector = Cpanel::Async::Connect->new();

    socket my $sock, AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0;

    my $cv = AnyEvent->condvar();

    $connector->connect(
        $sock,
        Socket::pack_sockaddr_in(443, Socket::inet_aton('1.2.3.4')),
    )->then(
        sub {
            print "connected\n";
        }
        sub($errno) {
            print "connect failed: $errno";
        },
    )->then($cv);

    $cv->recv();

=head1 DESCRIPTION

This module provides a convenient Promise wrapper around asynchronous
C<connect()>. It can be used with any socket that uses that system
call to initiate a connection: TCP, SCTP, etc.

Note that some socket types, like UDP or UNIX sockets, don’t actually
block on C<connect()>; for such sockets this module probably isn’t useful.

This module assumes use of L<AnyEvent>.

=head1 SEE ALSO

L<AnyEvent::Socket> includes similar functionality. (This module originally
didn’t use AnyEvent.) We could use that instead of writing out the logic,
but the logic savings would be fairly modest.

=cut

#----------------------------------------------------------------------

use Socket ();

use AnyEvent     ();
use Promise::ES6 ();

use Cpanel::Exception ();

use constant _EINPROGRESS => 115;

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->new()

Creates a new instance of this class.

=cut

sub new ($class) {
    my %data = (
        connecting => {},
    );

    return bless \%data, $class;
}

=head2 $promise = I<OBJ>->connect( $socket, $packed_addr )

Analogous to Perl’s built-in of the same name but returns a Promise object.
That promise will resolve with the given C<$socket>. It rejects with a
L<Cpanel::Exception::IO::SocketConnectError> instance or, I<maybe> in
bizarre cases, a L<Cpanel::Exception> with an untranslated C<getsockopt()>
error message.

=cut

sub connect ( $self, $socket, $packed_addr ) {
    my $fileno = fileno $socket;

    if ( $self->{'connecting'}{$fileno} ) {
        die "Already waiting on socket $fileno!";
    }

    AnyEvent->now_update();

    my $promise;
    if ( connect $socket, $packed_addr ) {
        $promise = Promise::ES6->resolve($socket);
    }
    elsif ( $! == _EINPROGRESS() ) {
        $promise = Promise::ES6->new(
            sub ( $y, $n ) {
                my $w = AnyEvent->io(
                    fh   => $socket,
                    poll => 'w',
                    cb   => sub {
                        $self->_process($fileno);
                    },
                );

                $self->{'connecting'}{$fileno} = [ $socket, $y, $n, $packed_addr, $w ];
            }
        );
    }
    else {
        my $errno = $!;

        $promise = Promise::ES6->reject(
            Cpanel::Exception::create(
                'IO::SocketConnectError',
                [ to => $packed_addr, error => $errno ],
            ),
        );
    }

    return $promise;
}

#=head2 $obj = I<OBJ>->process( @FDS_OR_FHS )
#
#@FDS_OR_FHS is a list of either file descriptors or Perl filehandles.
#
#Call this method after one or more sockets poll as writable.
#The associated promise objects will be resolved or rejected as appropriate.
#
#This returns I<OBJ>.
#
#B<IMPORTANT:> This assumes that each referenced socket is, in fact,
#writable. Behavior prior to socket writability is undefined.
#
#=cut

sub _process ( $self, @fds_or_fhs ) {

    for my $fd (@fds_or_fhs) {
        my $info_ar = $self->_delete_fd_or_fh_info($fd);

        my ( $socket, $y, $n, $packed_addr ) = @$info_ar;
        my $errno = getsockopt( $socket, Socket::SOL_SOCKET(), Socket::SO_ERROR() );

        # It seems unlikely that getsockopt() would ever fail
        # here, but we might as well check for it:
        if ( !defined $errno ) {
            $n->( Cpanel::Exception->create_raw("getsockopt(SOL_SOCKET, SO_ERROR): $!") );
        }
        elsif ( $errno = unpack 'i!', $errno ) {
            my $val = do { local $! = $errno; $! };

            $n->(
                Cpanel::Exception::create(
                    'IO::SocketConnectError',
                    [ to => $packed_addr, error => $val ],
                ),
            );
        }
        else {
            $y->($socket);
        }
    }

    return $self;
}

=head2 $obj = I<OBJ>->abort( $FD_OR_FH, $REASON )

Abort a given socket’s connection. $REASON will be given
as the associated promise’s rejection.

I<OBJ> is returned.

=cut

sub abort ( $self, $fd, $reason ) {
    my $info_ar = $self->_delete_fd_or_fh_info($fd);

    $info_ar->[2]->($reason);

    return $self;
}

#----------------------------------------------------------------------

=head2 @fds = I<OBJ>->get_connecting_fds()

A convenience method that returns the file descriptors whose connections
are still pending. (In scalar context this returns the number of such
file descriptors.)

=cut

sub get_connecting_fds ($self) {
    return keys %{ $self->{'connecting'} };
}

#----------------------------------------------------------------------

sub _delete_fd_or_fh_info ( $self, $fd ) {
    $fd = fileno($fd) if ref $fd;

    my $info_ar = delete $self->{'connecting'}{$fd} or do {
        die "FD $fd is not pending!";
    };

    return $info_ar;
}

1;
