package Cpanel::Async::AskDnsAdmin::Restarter;

# cpanel - Cpanel/Async/AskDnsAdmin/Restarter.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::AskDnsAdmin::Restarter

=head1 SYNOPSIS

    my $restarter = Cpanel::Async::AskDnsAdmin::Restarter->new('/path/to/socket');

    $restarter->on_connect_failure('it was bad')->then(
        sub ($socket) {
            printf "fileno: %d\n", fileno $socket;
        },
    );

=head1 DESCRIPTION

This module implements logic to restart dnsadmin and establish a new
connection to it that L<Cpanel::Async::AskDnsAdmin> can then use for
queries.

It should only be called on connection failure.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use AnyEvent    ();
use Promise::XS ();
use Socket      ();

use Cpanel::Autodie                        ();
use Cpanel::Async::Connect                 ();
use Cpanel::DnsUtils::AskDnsAdmin::Backend ();

# for mocking
our $_CONNECT_INTERVAL   = Cpanel::DnsUtils::AskDnsAdmin::Backend::CONNECT_INTERVAL;
our $_MAX_CONNECT_WINDOW = Cpanel::DnsUtils::AskDnsAdmin::Backend::MAX_TIME_TO_TRY_TO_CONNECT_TO_DNSADMIN;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $SOCKET_PATH )

Instantiates this class. $SOCKET_PATH is dnsadmin’s socket path.

(This is passed in rather than taken from
L<Cpanel::DnsUtils::AskDnsAdmin::Backend> in order to ensure that
whatever socket path the caller uses is what we use.)

=cut

sub new ( $class, $socket_path ) {
    return bless { path => $socket_path, tries => 0 }, $class;
}

=head2 promise($socket) = I<OBJ>->on_connect_failure( $ERROR )

To be called on a connection failure. This will return a promise
that:

=over

=item * … resolves with a newly-C<connect()>ed socket when we’re ready to
proceed

=item * … rejects if we exceed a timeout without verifying that the
socket is ready to retry

=item * … is pre-rejected, for when we’ve exceeded the max number of retries

=back

=cut

sub on_connect_failure ( $self, $error ) {
    if ( $self->{'tries'} == Cpanel::DnsUtils::AskDnsAdmin::Backend::MAX_CONNECT_RETRIES ) {

        # This should be rare since the first time we were called
        # we returned a promise that only resolves once we’ve
        # successfully connect()ed. So, assuming the caller is behaving
        # itself, we’d only get here if that subsequent attempt failed,
        # which is awfully unlikely.

        my $max_retries = Cpanel::DnsUtils::AskDnsAdmin::Backend::MAX_CONNECT_RETRIES;
        my $err         = "Exceeded max dnsadmin restart retries ($max_retries); last error was: $error";
        return Promise::XS::rejected($err);
    }

    $self->{'tries'}++;

    Cpanel::DnsUtils::AskDnsAdmin::Backend::restart_service();

    my $stop_at = time + $_MAX_CONNECT_WINDOW;

    my $deferred = Promise::XS::deferred();

    my ( $timer, $last_error );

    my $connector = Cpanel::Async::Connect->new();

    Cpanel::Autodie::socket(
        my $sock,
        Socket::AF_UNIX,
        Socket::SOCK_STREAM | Socket::SOCK_NONBLOCK,
        0,
    );

    my $sockpath = Socket::pack_sockaddr_un( $self->{'path'} );

    sub {
        my $try_again_cr = __SUB__;

        $timer = AnyEvent->timer(
            after => $_CONNECT_INTERVAL,
            cb    => sub {
                if ( time > $stop_at ) {
                    my $window = $_MAX_CONNECT_WINDOW;
                    $deferred->reject("Timed out (${window}s) while waiting for dnsadmin to be ready! Original error was: $error; last connect error was: $last_error");
                }
                else {
                    $connector->connect( $sock, $sockpath )->then(
                        sub { $deferred->resolve(@_) },
                        sub ($why) {
                            $last_error = $why;

                            $try_again_cr->();
                        },
                    );
                }
            },
        );
      }
      ->();

    return $deferred->promise();
}

1;
