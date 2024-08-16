package Cpanel::CommandStream::Client::Request::mailsync;

# cpanel - Cpanel/CommandStream/Client/Request/mailsync.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::Request::mailsync

=head1 SYNOPSIS

    # Let $requestor be an instance of
    # Cpanel::CommandStream::Client::Requestor …

    $req = $requestor->request(
        'mailsync',
        hostname  => 'somehost.tld',
        api_token => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345',
        username  => 'myuser',
    );

    $req->started_promise()->then(
        sub ($user_fate_hr) {
            for my $name (keys %$user_fate_hr) {
                my $promise = $user_fate_hr->{$name};

                # Do something with the name and the promise.
            }
        }
    } );

=head1 DESCRIPTION

This class implements controls for making CommandStream C<mailsync>
requests.

=head1 PARAMETERS

This module expects as arguments to the requestor’s C<request()> method:

=over

=item * C<hostname> - the remote host from which mail will be retrieved.

=item * C<api_token> - the API token to use to authenticate againt the remote host.

=item * C<username> - the user whose email accounts will be synchronized with the remote

=back

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Promise::XS ();

#----------------------------------------------------------------------

use constant {
    _STATE_START    => 'start',
    _STATE_STARTING => 'starting',
    _STATE_RUNNING  => 'running',
};

=head1 METHODS

=head2 promise(\%name_promise) = I<OBJ>->started_promise()

Returns a promise that resolves when all of the email account synchronizations
have started.

The promise’s resolution is a hashref whose names are the accounts being
synchronized; each value is a promise that resolves/rejects when the
synchronization completes. Once all of those promises finish, the request
is complete.

=cut

sub started_promise ($self) {
    return $self->{'_started_p'} ||= do {
        my $pt = $self->{'promise_tracker'};

        return $pt->add( $self->{'deferred'}->promise() )->then(
            sub ($name_fate_hr) {
                $_ = $pt->add($_) for values %$name_fate_hr;

                return $name_fate_hr;
            },
        );
    };
}

sub _create ( $promise_tracker, %opts ) {
    state @needs = qw( username hostname api_token );

    my @lacks = grep { !length $opts{$_} } @needs;

    die "Missing: @lacks" if @lacks;

    my $self = bless {
        promise_tracker => $promise_tracker,
        deferred        => Promise::XS::deferred(),
        state           => _STATE_START,
      },
      __PACKAGE__;

    my $handler_cr = sub ( $ctx, $msg_hr ) {
        my $fn = "_handler_$self->{'state'}";
        $self->$fn( $ctx, $msg_hr );
    };

    return ( $self, $handler_cr, %opts );
}

sub _unexpected_msg ($msg_hr) {
    my @pieces = map { $_ => $msg_hr->{$_} } sort keys %$msg_hr;
    return "Unexpected: @pieces";
}

sub _handler_start ( $self, $ctx, $msg_hr ) {
    if ( $msg_hr->{'class'} eq 'start' ) {
        $self->{'state'} = _STATE_STARTING;
        $self->_handler_starting( $ctx, $msg_hr );
    }
    else {
        $ctx->forget();
        $self->{'deferred'}->reject( _unexpected_msg($msg_hr) );
    }

    return;
}

sub _handler_starting ( $self, $ctx, $msg_hr ) {
    if ( $msg_hr->{'class'} eq 'start' ) {
        $self->{'_started'}{ $msg_hr->{'name'} } = Promise::XS::deferred();
    }
    elsif ( $msg_hr->{'class'} eq 'all_started' ) {
        my %started = %{ $self->{'_started'} };
        $_ = $_->promise() for values %started;

        $self->{'deferred'}->resolve( \%started );

        $self->{'state'} = _STATE_RUNNING;
    }
    else {
        $ctx->forget();
        $self->{'deferred'}->reject( _unexpected_msg($msg_hr) );
    }

    return;
}

sub _handler_running ( $self, $ctx, $msg_hr ) {
    my $msg_class = $msg_hr->{'class'};

    if ( $msg_class eq 'success' || $msg_class eq 'failure' ) {
        my $name = $msg_hr->{'name'};

        my $deferred = delete $self->{'_started'}{$name};

        if ( $msg_class eq 'success' ) {
            $deferred->resolve();
        }
        else {
            $deferred->reject( $msg_hr->{'why'} || '(unknown error)' );
        }
    }
    else {

        # If an unexpected message arrives, indicate it by failing all
        # pending syncs.

        my @pending = keys %{ $self->{'_started'} };

        my @deferreds = delete @{ $self->{'_started'} }{@pending};

        my $err = _unexpected_msg($msg_hr);

        $_->reject($err) for @deferreds;
    }

    if ( !%{ $self->{'_started'} } ) {
        $ctx->forget();
    }

    return;
}

1;
