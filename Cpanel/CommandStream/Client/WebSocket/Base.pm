package Cpanel::CommandStream::Client::WebSocket::Base;

# cpanel - Cpanel/CommandStream/Client/WebSocket/Base.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::WebSocket::Base

=head1 SYNOPSIS

See subclasses.

=head1 DESCRIPTION

This class subclasses L<Cpanel::CommandStream::Client::TransportBase>.
It creates a L<Cpanel::CommandStream::Client::Requestor> instance
using cpsrvd’s CommandStream WebSocket endpoint
(cf. L<Cpanel::Server::WebSocket::whostmgr::CommandStream>).

This class doesn’t implement authentication; for that, see an immediate
subclass of this one. End classes will subclass one of those authenticating
subclasses of this one, not this class itself directly.

=head1 SEE ALSO

L<Whostmgr::Remote::CommandStream::Legacy> provides a
L<Whostmgr::Remote>-compatible interface on top of this module.

L<Cpanel::CommandStream::Client::WebSocket::APIToken> provides a simpler
interface on top of L<Cpanel::CommandStream::Client::WebSocket>.

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::CommandStream::Client::TransportBase',
);

use AnyEvent        ();
use Sereal::Encoder ();

use Cpanel::Async::WebSocket      ();
use Cpanel::CommandStream::Client ();
use Cpanel::PromiseUtils          ();
use Cpanel::Sereal::Decoder       ();
use Cpanel::Services::Ports       ();

use constant {
    _DEBUG => 0,
};

use constant _REQUIRED => (
    qw( hostname username tls_verification ),
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Required %OPTS are:

=over

=item * C<hostname>

=item * C<username>

=item * C<tls_verification> (either C<on> or C<off>)

=item * … and whatever arguments are needed for authentication.
(The chosen subclass will define these.)

=back

B<NOTE:> The underlying connections are reaped when $obj is
garbage-collected.

=cut

sub new ( $class, %opts ) {
    my @req = $class->_REQUIRED();

    my @missing = grep { !length $opts{$_} } @req;
    die "missing: @missing" if @missing;

    %opts = (
        %opts{@req},
        _pid => $$,
    );

    return bless \%opts, $class;
}

#----------------------------------------------------------------------

=head1 PROTECTED METHODS

=head2 promise($requestor) = I<OBJ>->_Get_requestor_p()

Returns a promise whose resolution is a
L<Cpanel::CommandStream::Client::Requestor> instance.

=cut

sub _Get_requestor_p ($self) {

    my $courier_sr = \$self->{'_courier'};

    return $self->{'_requestor_p'} ||= do {
        my $port = $Cpanel::Services::Ports::SERVICE{'whostmgrs'};

        my ( $hname, $hval ) = $self->_get_http_authn_header();

        my $client = Cpanel::CommandStream::Client->new();

        my $sereal_enc = Sereal::Encoder->new();
        my $sereal_dec = Cpanel::Sereal::Decoder::create();

        my $tracker_obj = $self->_Get_promise_tracker();

        my $skip_finish_sr = \$self->{'_skip_finish'};

        _DEBUG && print STDERR "connecting WS\n";

        Cpanel::Async::WebSocket::connect(
            "wss://$self->{'hostname'}:$port/websocket/CommandStream?serialization=Sereal",
            insecure => $self->{'tls_verification'} eq 'off',
            headers  => [
                $hname => $hval,
            ],
            on => {
                binary => sub ($bytes) {
                    local $@;

                    if ( my $msg = eval { $sereal_dec->decode($bytes) } ) {
                        $client->handle_message($msg);
                    }
                    else {
                        $tracker_obj->reject_all(
                            "Sereal decode: $@",
                        );
                    }
                },

                close => sub ( $code, $reason ) {
                    _DEBUG && print STDERR "got premature WS close ($code $reason)\n";

                    $$skip_finish_sr = 1;

                    $tracker_obj->reject_all(
                        "The WebSocket connection closed prematurely ($code $reason)",
                    );
                },

                error => sub ($err) {
                    _DEBUG && print STDERR "WS failed: $err\n";

                    $$skip_finish_sr = 1;

                    $tracker_obj->reject_all(
                        "The WebSocket connection failed ($err)",
                    );
                },
            },
        )->then(
            sub ($courier) {
                _DEBUG && printf "%s: WS handshake done\n", __PACKAGE__;

                $$courier_sr = $courier;

                my $requestor = $client->create_requestor(
                    sub (%msg) {
                        _DEBUG && do {
                            require Cpanel::JSON;
                            print STDERR "out: " . Cpanel::JSON::canonical_dump( \%msg ) . "\n";
                        };

                        # Refer to $courier so that it lasts as long
                        # as the $requestor does.
                        $courier->send_binary( $sereal_enc->encode( \%msg ) )->catch(
                            sub ($why) {
                                my $err_txt = "Failed to send message: $why";
                                warn "$err_txt\n";

                                # We might still not have registered the
                                # request’s promise with $tracker_obj.
                                # To ensure that this rejection isn’t lost,
                                # delay it until the next loop run.
                                AnyEvent::postpone(
                                    sub {
                                        $tracker_obj->reject_all("Connection is no longer valid. ($err_txt)");
                                    }
                                );
                            }
                        );
                    },
                    $tracker_obj,
                );

                return $requestor;
            }
        );
    };
}

#----------------------------------------------------------------------

sub DESTROY ($self) {
    if ( !$self->{'_skip_finish'} && $$ == $self->{'_pid'} ) {
        if ( my $courier = $self->{'_courier'} ) {

            _DEBUG && print STDERR "sending SUCCESS close & waiting for response\n";

            Cpanel::PromiseUtils::wait_anyevent(
                $courier->finish('SUCCESS'),
            );

            _DEBUG && print STDERR "done waiting for response close\n";
        }
    }

    $self->SUPER::DESTROY();

    return;
}

1;
