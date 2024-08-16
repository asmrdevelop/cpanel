package Cpanel::Async::TLS;

# cpanel - Cpanel/Async/TLS.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::TLS - Convenient asynchronous TLS handshakes

=head1 SYNOPSIS

    use Cpanel::Socket::INET;
    use Cpanel::NetSSLeay::CTX;

    # NB: See Cpanel::Async::Connect if you want non-blocking connect().
    my $socket = Cpanel::Socket::INET->new("host.name:443");

    $socket->blocking(0);

    my $tls = Cpanel::Async::TLS->new();

    my $ctx = Cpanel::NetSSLeay::CTX->new();

    # You’ll probably also want to load a root certificate store, e.g.:
    require Mozilla::CA;
    $ctx_obj->load_verify_locations( Mozilla::CA::SSL_ca_file(), q<> );

    my $cv = AnyEvent->condvar();

    $tls->connect(
        $ctx, $socket,
        SSL_hostname => 'host.name',
    )->then(
        sub($ssl_obj) {
            print "handshake succeeded\n";
        }
        sub($err) {
            # … handle
        },
    )->then($cv);

    $cv->recv();

=head1 DESCRIPTION

This module provides a convenient-ish Promise wrapper around asynchronous
TLS handshakes.

This is designed less for actual TLS sessions than for just doing the
handshake. For an actual TLS session you’d probably want to find some way
to feed the result of this module’s handshake into L<IO::Socket::SSL>.

It would be feasible to implement this module via L<IO::Socket::SSL>,
but it doesn’t actually save a lot of effort; most of the “heavy lifting”
happens in L<Net::SSLeay> itself.

This module assumes use of L<AnyEvent>.

=head1 SEE ALSO

CPAN’s L<AnyEvent::TLS> provides a similar feature set but doesn’t expose
the same level of detail about the TLS handshake.

=cut

#----------------------------------------------------------------------

use Net::SSLeay  ();
use Promise::ES6 ();

use Cpanel::Exception                ();
use Cpanel::NetSSLeay::SSL           ();
use Cpanel::NetSSLeay::ErrorHandling ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    Net::SSLeay::initialize() if Net::SSLeay::library_init();

    my %data = (
        pending => {},
    );

    return bless \%data, $class;
}

=head2 $promise = I<OBJ>->connect( $CTX_OBJ, $SOCKET, %OPTS )

Initiates a TLS handshake on $SOCKET. $CTX_OBJ is a L<Cpanel::NetSSLeay::CTX>
instance.

%OPTS are:

=over

=item * C<SSL_hostname> - (optional) The SNI string to send in the Client Hello.

=back

The return is a Promise object that both resolves and rejects with a
L<Cpanel::NetSSLeay::SSL> object that represents the TLS handshake.

=cut

sub connect ( $self, $ctx_obj, $socket, %opts ) {
    my $hostname = delete $opts{'SSL_hostname'};

    if ( my @bad = keys %opts ) {
        die "Unrecognized: [@bad]";
    }

    my $ssl_obj = Cpanel::NetSSLeay::SSL->new($ctx_obj);
    $ssl_obj->set_fd( fileno $socket );

    $ssl_obj->set_tlsext_host_name($hostname) if length $hostname;

    # We call this function rather than $ssl_obj’s method in order
    # to avoid creating an exception in the incomplete case.
    my $rv = Net::SSLeay::connect( $ssl_obj->PTR() );

    my $info_hr = {
        ssl_obj => $ssl_obj,
        socket  => $socket,
        fd      => fileno($socket),
    };

    my $promise = Promise::ES6->new( sub { @{$info_hr}{ 'y', 'n' } = @_ } );

    AnyEvent->now_update();

    $self->_process_connect_result( $ssl_obj, $rv, $info_hr );

    return $promise;
}

#=head2 @statuses = I<OBJ>->process( @FDS_OR_FHS )
#
#Rerun C<Net::SSLeay::connect()> on the given sockets, represented as either
#file descriptors or Perl filehandles. Any completed handshakes will prompt
#resolution or rejection of the corresponding promises from C<connect()>.
#
#The return is a list of C<Net::SSLeay::get_error()> returns that indicate
#the state of each referenced socket’s TLS handshake. In particular,
#C<Net::SSLeay::ERROR_WANT_READ()> means OpenSSL needs to read on the socket,
#while C<Net::SSLeay::ERROR_WANT_WRITE()> means OpenSSL needs to write on it.
#
#=cut

sub _process ( $self, @fds ) {
    my @ret;

    for my $fd (@fds) {
        $fd = fileno($fd) if ref $fd;

        my $info_hr = $self->{'pending'}{$fd};

        my $ssl_obj = $info_hr->{'ssl_obj'};
        my $rv      = Net::SSLeay::connect( $ssl_obj->PTR() );

        push @ret, $self->_process_connect_result( $ssl_obj, $rv, $info_hr );
    }

    return @ret;
}

=head2 $obj = I<OBJ>->abort( $FD_OR_FH, $REASON )

Abort a given socket’s TLS handshake. $REASON will be given
as the associated promise’s rejection.

I<OBJ> is returned.

=cut

sub abort ( $self, $fd, $reason ) {
    $fd = fileno($fd) if ref $fd;

    my $info_hr = $self->_delete_info_hr($fd);

    $info_hr->{'n'}->($reason);

    return $self;
}

=head2 @fds = I<OBJ>->get_pending_fds()

A convenience method that returns the file descriptors whose TLS handshakes
are in progress. (In scalar context this returns the number of such
file descriptors.)

=cut

sub get_pending_fds ($self) {
    return keys %{ $self->{'pending'} };
}

#----------------------------------------------------------------------

sub _delete_info_hr ( $self, $fd ) {
    my $was = delete $self->{'pending'}{$fd};

    return $was;
}

sub _finish ( $self, $succeed_yn, $info_hr ) {
    my $fd = $info_hr->{'fd'};

    $self->_delete_info_hr($fd);

    my $which = $succeed_yn ? 'y' : 'n';

    my $arg = $succeed_yn ? $info_hr->{'ssl_obj'} : do {
        my $errno     = $!;
        my @err_codes = Cpanel::NetSSLeay::ErrorHandling::get_error_codes();

        Cpanel::Exception::create(
            'NetSSLeay',
            [
                function    => 'connect',
                arguments   => [],
                error_codes => \@err_codes,
                errno       => $errno,
            ],
        );
    };

    $info_hr->{$which}->($arg);

    return;
}

sub _process_connect_result ( $self, $ssl_obj, $rv, $info_hr ) {    ## no critic qw(ManyArgs) - misparse
    my $err = Net::SSLeay::get_error( $ssl_obj->PTR(), $rv );

    if ( $rv < 0 ) {
        if ( $err == Net::SSLeay::ERROR_WANT_READ() ) {
            $self->_set_anyevent_poll( $info_hr, 'r' );
        }
        elsif ( $err == Net::SSLeay::ERROR_WANT_WRITE() ) {
            $self->_set_anyevent_poll( $info_hr, 'w' );
        }
        else {
            $self->_finish( 0, $info_hr );
        }
    }
    else {
        $self->_finish( !!$rv, $info_hr );
    }

    return $err;
}

sub _set_anyevent_poll ( $self, $info_hr, $direction ) {
    my $fd = $info_hr->{'fd'};

    if ( !$info_hr->{'poll'} || $info_hr->{'poll'} ne $direction ) {
        @{$info_hr}{ 'poll', 'wait_obj' } = (
            $direction,
            AnyEvent->io(
                fh   => $fd,
                poll => $direction,
                cb   => sub { $self->_process($fd) },
            ),
        );
    }

    $self->{'pending'}{$fd} ||= $info_hr;

    return;
}

1;
