package Cpanel::CommandStream::Client::Request::tardownload;

# cpanel - Cpanel/CommandStream/Client/Request/tardownload.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::Request::tardownload

=head1 SYNOPSIS

    my $req = $requestor->request(
        'tardownload',

        hostname => 'the.other.server',
        api_token => 'ITISASECRET',
        username => 'bob',
        tls_verification => 'on',

        local_directory => '/put/things/here',
        remote_directory => '/grab/from/here',
        paths => ['foo', 'bar'],
    );

    my $w = $req->create_warn_subscription( sub ($msg) {

        # You probably want something a bit more “refined”,
        # but just for demonstration purposes:
        warn $msg;
    } );

    $req->started_promise()->then(
        sub {
            print "Started\n";

            return $req->done_promise();
        },
    )->then(
        sub { print "Done\n" },
    );

=head1 DESCRIPTION

This module implements client logic for CommandStream C<tardownload>
requests.

See L<Cpanel::CommandStream::Handler::tardownload> for more details.

=cut

#----------------------------------------------------------------------

use Carp ();

use parent 'Cpanel::Destruct::DestroyDetector';

use Cpanel::Event::Emitter ();

use constant {
    _STATE_STARTING => 'starting',
    _STATE_STARTED  => 'started',
};

my %HANDLER = (
    _STATE_STARTING() => {

        started => sub ( $self, $ctx, $msg_hr ) {
            $self->{'state'} = _STATE_STARTED;
            $self->{'starting_deferred'}->resolve();
        },
    },

    _STATE_STARTED() => {
        warn => sub ( $self, $ctx, $msg_hr ) {
            $self->{'emitter'}->emit_or_warn( warn => $msg_hr->{'content'} );
        },
        done => sub ( $self, $ctx, $msg_hr ) {
            $ctx->forget();
            $self->{'started_deferred'}->resolve();
        },
    },
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $subscr = I<OBJ>->create_warn_subscription( $TODO_CR )

Returns a L<Cpanel::Event::Emitter::Subscription> for C<warn>
messages.

=cut

sub create_warn_subscription ( $self, $callback ) {
    return $self->_create_subscription( warn => $callback );
}

=head2 promise() = I<OBJ>->started_promise()

Returns a promise that resolves once the tar download has started.
(This will probably fire soon after the server receives the request.)

=cut

sub started_promise ($self) {
    return $self->{'_started_p'} ||= do {
        my $p = $self->{'starting_deferred'}->promise();

        return $self->{'promise_tracker'}->add($p);
    };
}

=head2 promise() = I<OBJ>->done_promise()

Returns a promise that resolves once the tar download is done.

=cut

sub done_promise ($self) {
    return $self->{'_done_p'} ||= do {
        my $d = $self->{'started_deferred'};

        my $p = $self->started_promise()->then( sub { $d->promise() } );

        return $self->{'promise_tracker'}->add($p);
    };
}

#----------------------------------------------------------------------

sub _create ( $promise_tracker, %opts ) {
    state @needs = qw(
      username hostname api_token tls_verification
      local_directory remote_directory paths
    );

    state %tls_verified_value = (
        on  => 1,
        off => 0,
    );

    my @lacks = grep { !length $opts{$_} } @needs;

    Carp::confess "Missing: @lacks" if @lacks;

    for ('tls_verification') {
        if ( $opts{$_} ne 'on' && $opts{$_} ne 'off' ) {
            Carp::confess "Bad “$_”: $opts{$_}";
        }
    }

    my %extras = %opts;
    delete @extras{@needs};

    if ( my @names = sort keys %extras ) {
        Carp::confess "Extra: @names";
    }

    my $self = bless {
        promise_tracker   => $promise_tracker,
        starting_deferred => Promise::XS::deferred(),
        started_deferred  => Promise::XS::deferred(),
        emitter           => Cpanel::Event::Emitter->new(),
        state             => _STATE_STARTING,
      },
      __PACKAGE__;

    my $handler_cr = sub ( $ctx, $msg_hr ) {
        my $state_handler_hr = $HANDLER{ $self->{'state'} } or do {
            die "$self: Unknown state $self->{'state'}!";
        };

        my $fn = $state_handler_hr->{ $msg_hr->{'class'} };
        $fn ||= '_fail_from_msg';

        $self->$fn( $ctx, $msg_hr );
    };

    return ( $self, $handler_cr, %opts );
}

sub _create_subscription ( $self, $stream, $cb ) {
    return $self->{'emitter'}->create_subscription( $stream, $cb );
}

sub _fail_from_msg ( $self, $ctx, $msg_hr ) {
    $ctx->forget();

    my $why;

    if ( $msg_hr->{'class'} eq 'failed' ) {
        $why = $msg_hr->{'why'};
    }
    else {
        $why = _unexpected_msg($msg_hr);
    }

    my $deferred = $self->{"$self->{'state'}_deferred"};
    $deferred->reject($why);

    return;
}

sub _unexpected_msg ($msg_hr) {
    my @pieces = map { $_ => $msg_hr->{$_} } sort keys %$msg_hr;
    return "Unexpected: @pieces";
}

1;
