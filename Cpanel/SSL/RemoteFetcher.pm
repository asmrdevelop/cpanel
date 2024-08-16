package Cpanel::SSL::RemoteFetcher;

# cpanel - Cpanel/SSL/RemoteFetcher.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::RemoteFetcher

=head1 DESCRIPTION

This module encapsulates logic to fetch remote TLS hosts’s certificate chains.

=cut

#----------------------------------------------------------------------

use Socket      ();
use Mozilla::CA ();
use Net::SSLeay ();

use Cpanel::Async::Connect ();
use Cpanel::Async::TLS     ();
use Cpanel::Autodie        ();
use Cpanel::NetSSLeay::CTX ();

# Overridden in tests
our $_CONNECT_TIMEOUT = 10;
our $_TLS_TIMEOUT     = 10;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    Net::SSLeay::initialize() if Net::SSLeay::library_init();

    my $ctx_obj = Cpanel::NetSSLeay::CTX->new();

    $ctx_obj->load_verify_locations( Mozilla::CA::SSL_ca_file(), q<> );

    my $connect = Cpanel::Async::Connect->new();
    my $tls     = Cpanel::Async::TLS->new();

    return bless {
        _ctx     => $ctx_obj,
        _connect => $connect,
        _tls     => $tls,
    }, $class;
}

=head2 $promise = I<OBJ>->fetch( $hostname, $port )

Returns a promise whose resolution is a hash reference like:

=over

=item * C<chain> - Reference to an array of certificates in PEM format.

=item * C<handshake_verify> - A number that represents the state of the
TLS handshake’s verification.

You can convert this to a string via L<Cpanel::OpenSSL::Verify>.

=back

=cut

sub fetch ( $self, $hostname, $port ) {
    my ( $ctx_obj, $connect, $tls ) = @{$self}{qw( _ctx _connect _tls )};

    Cpanel::Autodie::socket( my $s, Socket::AF_INET(), Socket::SOCK_STREAM() | Socket::SOCK_NONBLOCK(), 0 );

    my $ipv4 = Socket::inet_aton($hostname) or die "“$hostname” doesn’t resolve to IPv4!";
    my $addr = Socket::pack_sockaddr_in( $port, $ipv4 );

    my $tcp_promise = $connect->connect( $s, $addr );

    my $tcp_timeout = AnyEvent->timer(
        after => $_CONNECT_TIMEOUT,
        cb    => sub { $connect->abort( $s, 'connect() timeout' ) },
    );

    $tcp_promise->finally( sub { undef $tcp_timeout } );

    my $promise = $tcp_promise->then(
        sub {
            my $tls_timeout = AnyEvent->timer(
                after => $_TLS_TIMEOUT,
                cb    => sub { $tls->abort( $s, 'TLS handshake timeout' ) },
            );

            my $tls_promise = $tls->connect(
                $ctx_obj, $s,
                SSL_hostname => $hostname,
            );

            $tls_promise->finally( sub { $tls_timeout = undef } );

            return $tls_promise;
        },
    )->then(
        sub ($ssl_obj) {
            my $ssl = $ssl_obj->PTR();

            my @chain = Net::SSLeay::get_peer_cert_chain($ssl);
            my @pems  = map { Net::SSLeay::PEM_get_string_X509($_) } @chain;
            chomp for @pems;

            return {
                chain            => \@pems,
                handshake_verify => Net::SSLeay::get_verify_result($ssl),
            };
        },
    );

    return $promise;
}

1;
