package Cpanel::CommandStream::Client::Request::exec;

# cpanel - Cpanel/CommandStream/Client/Request/exec.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::Request::exec

=head1 SYNOPSIS

    # Let $requestor be an instance of
    # Cpanel::CommandStream::Client::Requestor …

    $req = $requestor->request(
        'exec',
        command => [ '/path/to/command', 'arg1', 'arg2' ],
        stdin => 'I am optional.',
    );

    my $subscr = $req->create_stdout_subscription(
        sub ($chunk) { .. },
    );

    $req->promise()->then( sub ($status) {
        if ($status) {
            # nonzero exit status
        }
    } );

=head1 DESCRIPTION

This class implements controls for making CommandStream requests.

=head1 PARAMETERS

This module expects as arguments to the requestor’s C<request()> method:

=over

=item * C<command> - a command path and arguments

=item * C<stdin> - optional, a buffer to send as the remote process’s
standard input

=back

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use Promise::XS ();

use Cpanel::Event::Emitter ();

use constant {
    _STATE_START       => 'start',
    _STATE_RUNNING     => 'running',
    _STATE_IO_COMPLETE => 'io_complete',
};

my %FINISH_MASK = (
    stdout => 1,
    stderr => 2,
);

my $ALL_DONE = 0;
$ALL_DONE |= $_ for values %FINISH_MASK;

#----------------------------------------------------------------------

=head1 METHODS

=head2 $subscr = I<OBJ>->create_stdout_subscription( $CALLBACK )

Creates a L<Cpanel::Event::Emitter> subscription for the remote
process’s STDOUT.

=cut

sub create_stdout_subscription ( $self, $callback ) {
    return $self->_create_subscription( stdout => $callback );
}

=head2 $subscr = I<OBJ>->create_stderr_subscription( $CALLBACK )

Like C<create_stdout_subscription()> but for STDERR.

=cut

sub create_stderr_subscription ( $self, $callback ) {
    return $self->_create_subscription( stderr => $callback );
}

=head2 $promise = I<OBJ>->promise()

Returns a promise that resolves when the process reports its end
(whether that’s a zero exit or not). If anything else happens, the
promise rejects.

=cut

sub promise ($self) {
    return $self->{'deferred'}->promise();
}

#----------------------------------------------------------------------

# First arg here is a $promise_tracker. We happen not to need it since
# everything currently that calls this code adds the promises to the
# promise tracker separately. It may be nice to clean that up a bit and
# have the promise-tracker stuff happen here instead.
#
sub _create ( $, %opts ) {
    die 'need command' if !$opts{'command'};

    my $self = bless {
        io_finished => 0,
        deferred    => Promise::XS::deferred(),
        emitter     => Cpanel::Event::Emitter->new(),
        state       => _STATE_START,
      },
      __PACKAGE__;

    my $handler_cr = sub ( $ctx, $msg_hr ) {
        my $fn = "_handler_$self->{'state'}";

        $self->$fn( $ctx, $msg_hr );
    };

    # Avoid submitting (stdin => undef).
    my @args = %opts{
        'command',
        ( length( $opts{'stdin'} ) ? 'stdin' : () ),
    };

    return ( $self, $handler_cr, @args );
}

#----------------------------------------------------------------------

sub _create_subscription ( $self, $stream, $cb ) {
    return $self->{'emitter'}->create_subscription( $stream, $cb );
}

sub _unexpected_msg ($msg_hr) {
    my @pieces = map { $_ => $msg_hr->{$_} } sort keys %$msg_hr;

    return "Unexpected: @pieces";
}

sub _handler_start ( $self, $ctx, $msg_hr ) {
    if ( $msg_hr->{'class'} eq 'exec_ok' ) {
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

    if ( $msg_class eq 'stdin_failed' ) {
        warn "$self: stdin failed ($msg_hr->{'text'})";
    }
    elsif ( $msg_class eq 'stdout_failed' || $msg_class eq 'stderr_failed' ) {
        my ($stream) = split m<_>, $msg_class;

        warn "$self: $stream failed ($msg_hr->{'text'})";

        $self->{'io_finished'} |= $FINISH_MASK{$stream};
    }
    elsif ( $msg_class eq 'stdout' || $msg_class eq 'stderr' ) {
        if ( length $msg_hr->{'chunk'} ) {
            $self->{'emitter'}->emit( $msg_class => $msg_hr->{'chunk'} );
            return;
        }
        else {
            $self->{'io_finished'} |= $FINISH_MASK{$msg_class};
        }
    }
    else {
        $ctx->forget();
        $self->{'deferred'}->reject( _unexpected_msg($msg_hr) );
        return;
    }

    if ( $self->{'io_finished'} == $ALL_DONE ) {
        $self->{'state'} = _STATE_IO_COMPLETE;
    }

    return;
}

sub _handler_io_complete ( $self, $ctx, $msg_hr ) {
    $ctx->forget();

    my $d = $self->{'deferred'};

    if ( $msg_hr->{'class'} eq 'ended' ) {
        $d->resolve( $msg_hr->{'status'} );
    }
    else {
        $d->reject( _unexpected_msg($msg_hr) );
    }

    return;
}

1;
