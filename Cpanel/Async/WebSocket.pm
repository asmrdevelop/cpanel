package Cpanel::Async::WebSocket;

# cpanel - Cpanel/Async/WebSocket.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::WebSocket

=head1 SYNOPSIS

    my $client_p = Cpanel::Async::WebSocket::connect(
        'wss://where.to/path/to?query'
        compression => 'deflate',
        headers => [
            'Authorization'   => 'cpanel bob:BOBSTOKEN',
            'X-SomethingElse' => 'other value',
        ],
    );

    my $cv = AnyEvent->condvar();

    $client_p->then(
        sub ($courier) {

            # Your WebSocket session goes in here.

            $cv->();
        },
        sub ($why) { $cv->croak($why) },
    );

    $cv->recv();

=head1 DESCRIPTION

This module implements an easy-to-use WebSocket client. It’s similar in
scope to L<Mojo::UserAgent>’s WebSocket functionality but should be
considerably lighter.

=cut

#----------------------------------------------------------------------

use IO::Framed                        ();
use IO::Socket::SSL                   ();
use HTTP::Response                    ();
use Net::WebSocket::Handshake::Client ();
use Net::WebSocket::HTTP_R            ();
use Promise::ES6                      ();
use URI::Split                        ();
use Socket                            ();

use Cpanel::Autodie                   ();
use Cpanel::Async::IOSocketSSL        ();
use Cpanel::Async::WebSocket::Courier ();

our %SCHEME_PORT = (
    ws  => 80,
    wss => 443,
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise($courier) = connect( $URL, %OPTS )

Starts a WebSocket connection to $URL. Returns a promise that resolves
to a L<Cpanel::Async::WebSocket::Courier> instance when that connection
is ready for use.

%OPTS are:

=over

=item * C<compression> - (optional) Dictates which kind of WebSocket
compression to attempt to use. Either C<deflate> (default) or C<none>.

=item * C<headers> - (optional) Arrayref of key-value pairs to include
with the HTTP handshake request.

=item * C<insecure> - (optional) Boolean, indicates to forgo SSL
verification.

=item * C<on> - (optional) Hashref of listeners to create upon
instantiation. Passed along to the courier object constructor.
This is a pure convenience; you can as easily set watchers in the
promise’s callback.

=back

Currently there is no support for subprotocols, but this would be easy
to add if that’s useful.

=cut

sub connect ( $url, %raw_opts ) {
    my %opts = %raw_opts{ 'compression', 'headers', 'on', 'insecure' };

    delete @raw_opts{ keys %opts };
    if ( my @extra = %raw_opts ) {
        die( __PACKAGE__ . ": Unrecognized: @extra" );
    }

    if ( my $events_hr = $opts{'on'} ) {
        Cpanel::Async::WebSocket::Courier::validate_events($events_hr);
    }

    my ( $scheme, $authority ) = URI::Split::uri_split($url);

    # Require SSL for now.
    if ( !$scheme || !$SCHEME_PORT{$scheme} ) {
        die "Bad WebSocket URI: $url";
    }

    $opts{'compression'} //= 'deflate';

    my $deflate;
    if ( defined $opts{'compression'} ) {
        if ( $opts{'compression'} eq 'deflate' ) {
            require Net::WebSocket::PMCE::deflate::Client;
            $deflate = Net::WebSocket::PMCE::deflate::Client->new();
        }
        elsif ( $opts{'compression'} ne 'none' ) {
            die "Bad “compression”: $opts{'compression'}";
        }
    }

    my ( $host, $port ) = split m<:>, $authority;

    my $addr = _hostname_to_packed_addr( $scheme, $host, $port );

    my $after_connect = sub ($s) {
        _after_connect( $s, $url, $deflate, \%opts );
    };

    # Assumedly unencrypted HTTP will be for debugging only.
    # But we might as well allow it.
    if ( $scheme eq 'ws' ) {
        Cpanel::Autodie::socket( my $s, Socket::sockaddr_family($addr), Socket::SOCK_STREAM | Socket::SOCK_NONBLOCK, 0 );

        require Cpanel::Async::Connect;
        return Cpanel::Async::Connect->new()->connect( $s, $addr )->then(
            $after_connect,
        );
    }

    return Cpanel::Async::IOSocketSSL::create(
        $addr,
        SSL_hostname => $host,
        ( $opts{'insecure'} ? ( SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE() ) : () ),
    )->then(
        $after_connect,
    );
}

sub _hostname_to_packed_addr ( $scheme, $host, $port ) {

    # This will do a DNS lookup. It’ll block, alas, but it should
    # at least be fast under most circumstances. Let’s also assume
    # that IPv4 is OK.
    my $addr = Socket::inet_aton($host) or do {
        my $msg = "“$host” has no IP address!";
        $msg .= " ($!)" if $!;
        die "$msg\n";
    };

    return Socket::pack_sockaddr_in(
        $port || $SCHEME_PORT{$scheme},
        $addr,
    );
}

sub _after_connect ( $socket, $url, $deflate, $opts_hr ) {
    my $handshake = Net::WebSocket::Handshake::Client->new(
        uri => $url,
        ( $deflate ? ( extensions => [$deflate] ) : () ),
    );

    my $hdr = $handshake->to_string( headers => $opts_hr->{'headers'} );

    my $framed = IO::Framed->new($socket)->enable_write_queue();

    my %read_during_handshake_opts = (
        %$opts_hr,
        socket     => $socket,
        framed     => $framed,
        handshake  => $handshake,
        compressor => $deflate,
    );

    return Promise::ES6->new(
        sub ( $y, $n ) {
            $framed->write(
                $hdr,
                sub {
                    my $watch;
                    $watch = AnyEvent->io(
                        fh   => $socket,
                        poll => 'r',
                        cb   => sub {
                            my $ok = eval {
                                if ( my $courier = _read_during_handshake( \%read_during_handshake_opts ) ) {
                                    undef $watch;
                                    $y->($courier);
                                }

                                1;
                            };

                            if ( !$ok ) {
                                undef $watch;
                                $n->($@);
                            }
                        },
                    );
                },
            );

            $framed->flush_write_queue() or do {
                die "Unhandled partial send of handshake headers!";
            };
        }
    );
}

sub _read_during_handshake ($opts_hr) {
    my ( $framed, $handshake, $compressor ) = @{$opts_hr}{ 'framed', 'handshake', 'compressor' };

    if ( my $hdr2 = $framed->read_until("\x0d\x0a\x0d\x0a") ) {
        my $resp = HTTP::Response->parse($hdr2);

        Net::WebSocket::HTTP_R::handshake_consume_response(
            $handshake,
            $resp,
        );

        my $compressor_data;

        if ( $compressor && $compressor->ok_to_use() ) {

            # _debug('permessage-deflate extension accepted.');
            $compressor_data = $compressor->create_data_object();
        }

        my $courier = Cpanel::Async::WebSocket::Courier->new(
            %{$opts_hr}{ 'socket', 'framed', 'on' },
            subprotocol => $handshake->get_subprotocol(),
            compressor  => $compressor_data,
        );

        return $courier;
    }

    return undef;
}

1;
