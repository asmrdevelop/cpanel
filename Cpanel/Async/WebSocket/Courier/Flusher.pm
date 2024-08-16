package Cpanel::Async::WebSocket::Courier::Flusher;

# cpanel - Cpanel/Async/WebSocket/Courier/Flusher.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::WebSocket::Courier::Flusher

=head1 SYNOPSIS

    my $flusher = Cpanel::Async::WebSocket::Courier::Flusher->new(
        socket => $s,
        framed => $framed_obj,
        on_writable_et => sub { .. },
    );

=head1 DESCRIPTION

This module encapsulates the pieces of
L<Cpanel::Async::WebSocket::Courier> that concern flushing the write
queue. It’s useful to have these pieces in a separate object in order
to avoid circular references.

It may be useful in other contexts, too? (If that ends up being the
case we should rename this module.)

=cut

#----------------------------------------------------------------------

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class.

%OPTS are:

=over

=item * C<socket> - A perl filehandle that represents the
underlying TCP connection.

=item * C<framed> - An L<IO::Framed> instance that wraps the
C<socket>.

=item * C<on_writable_et> - Callback that fires after C<socket>
I<transitions> to a writable state and a flush has happened.
Called with a single argument: a boolean that indicates whether
the write queue is now empty or not.

(NB: C<et> is for “edge-triggered”.)

=back

=cut

sub new ( $class, %opts ) {
    return bless \%opts, $class;
}

#----------------------------------------------------------------------

=head2 $yn = I<OBJ>->flush()

Flushes the write queue. If immediately successful returns truthy;
otherwise returns falsy and configures L<AnyEvent> to flush the
queue again when the socket is writable. The on-writable callback
fires at that time. (NB: That callback fires I<even> if the write
queue is still nonempty after the subsequent flush.)

=cut

sub flush ($self) {
    return 1 if $self->{'framed'}->flush_write_queue();

    $self->_watch_write();
    return 0;
}

=head2 I<OBJ>->stop()

Makes I<OBJ> stop trying to write. (This is a no-op if it’s not
currently trying to write.)

=cut

sub stop ($self) {
    undef $self->{'write_watch'};

    return;
}

sub _watch_write ($self) {

    if ( !$self->{'write_watch'} ) {
        my $on_writable_cr = $self->{'on_writable_et'};

        my $framed = $self->{'framed'};

        my $ww_ref = \$self->{'write_watch'};

        my $queue_is_empty;

        $$ww_ref = AnyEvent->io(
            fh   => $self->{'socket'},
            poll => 'w',
            cb   => sub {
                $queue_is_empty = $framed->flush_write_queue();

                $on_writable_cr->($queue_is_empty);

                $$ww_ref = undef if $queue_is_empty;
            },
        );
    }

    return;
}

1;
