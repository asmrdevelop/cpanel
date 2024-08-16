package Cpanel::Async::IOSocketSSL;

# cpanel - Cpanel/Async/IOSocketSSL.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::IOSocketSSL

=head1 SYNOPSIS

    Cpanel::Async::IOSocketSSL::create(
        Socket::pack_sockaddr_in( 443, Socket::inet_aton('88.77.66.55') ),
        SSL_hostname => 'example.com',
    )->then( sub ($socket) {

        # $socket isa IO::Socket::SSL
    } );

=head1 DESCRIPTION

This module establishes a TLS session via L<IO::Socket::SSL> using
non-blocking I/O. It’s similar to L<Cpanel::Async::TLS> except that it
only exposes IO::Socket::SSL’s tools for error reporting, which aren’t
quite as detailed as those in Cpanel::Async::TLS.

This module assumes use of L<AnyEvent> but could be altered relatively
easily to work with a different event loop interface.

=cut

#----------------------------------------------------------------------

use AnyEvent        ();
use IO::Socket::SSL ();
use Promise::ES6    ();
use Socket          ();

use Cpanel::Autodie        ();
use Cpanel::Async::Connect ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise($obj) = create( $PACKED_ADDR, %SSL_OPTS )

Creates a socket, C<connect()>s it to $PACKED_ADDR, and initiates a TLS
connection.

%SSL_OPTS are given to IO::Socket::SSL. (A warning is thrown if no
C<SSL_hostname> is given.)

The returned promise resolves to an IO::Socket::SSL instance.

=cut

sub create ( $packed_addr, %ssl_opts ) {
    if ( !$ssl_opts{'SSL_hostname'} ) {
        warn 'No “SSL_hostname” given; that’s probably wrong.';
    }

    Cpanel::Autodie::socket(
        my $socket,
        Socket::sockaddr_family($packed_addr),
        Socket::SOCK_STREAM | Socket::SOCK_NONBLOCK,
        0,
    );

    # ensure anyevent time is updated before
    # starting
    AnyEvent->now_update();

    my $connector = Cpanel::Async::Connect->new();

    return $connector->connect( $socket, $packed_addr )->then(
        sub ($s) {
            $s = IO::Socket::SSL->new_from_fd(
                fileno $s,
                %ssl_opts,
                Blocking           => 0,
                SSL_startHandshake => 0,
            );

            return Promise::ES6->new(
                sub ( $y, $n ) {
                    my $watch;

                    my $on_readable = sub {
                        if ( $s->connect_SSL() ) {
                            $y->($s);
                        }
                        elsif ( !$!{'EWOULDBLOCK'} ) {
                            $n->($IO::Socket::SSL::SSL_ERROR);
                        }
                        else {
                            return;
                        }

                        undef $watch;
                    };

                    $watch = AnyEvent->io(
                        fh   => $s,
                        poll => 'r',
                        cb   => $on_readable,
                    );

                    $on_readable->();
                }
            );
        },
    );

}

1;
