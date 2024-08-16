package Cpanel::Promise::Interruptible;

# cpanel - Cpanel/Promise/Interruptible.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Promise::Interruptible

=head1 SYNOPSIS

    my $request = _create_request();

    my $promise = _start_request($request);

    my $cancelable_promise = Cpanel::Promise::Interruptible->new(
        $promise,
        sub { _cancel_request($request) },
    );

    # calls $request->cancel():
    $cancelable_promise->interrupt();

=head1 DESCRIPTION

This promise class provides a mechanism for a promise “consumer” to
“interrupt”—i.e., send a message to—the “producer”, assumedly while
the promise is still pending.

=head1 POTENTIAL USES

B<IMPORTANT:> Whatever happens when C<interrupt()> is called B<MUST>
be documented as part of the producer’s interface. See
L<Cpanel::DNS::Unbound::Async> for an example.

=head2 Cancellation

The most immediate use for this module is in facilitating promise
cancellation: letting the “producer” side of a promise know that the
“consumer” no longer cares about the promise’s resolution.

=head2 Progress Report

A consumer might want to ask the producer for a “status report”.
(Heh, that value could even be returned in a promise!)

=head1 SEE ALSO

L<bluebird.js|http://bluebirdjs.com> was the inspiration for this design.
It’s probably the most popular promise cancellation implementation.

=cut

#----------------------------------------------------------------------

our %_CANCELER;

#----------------------------------------------------------------------

=head1 NONSTANDARD METHODS

=head2 $obj = I<CLASS>->new( $PROMISE, $ON_INTERRUPT_CR )

Creates a “shim” promise that wraps the given $PROMISE. This should
be called on the I<producer> side of the promise.

The returned $obj’s C<interrupt()> method is a passthrough to the
given $ON_INTERRUPT_CR coderef.

=cut

sub new ( $class, $promise, $on_interrupt ) {
    return bless [ $promise, $on_interrupt ], $class;
}

=head2 ? = I<OBJ>->interrupt( @VALUES )

Invokes the $ON_INTERRUPT_CR callback given to C<new()>, with
@VALUES—which may be empty—given as argument.

The return from that callback is passed on to the C<interrupt()> caller,
in whatever calling context—void, scalar, or list—pertains to the
C<interrupt()> call.

=cut

sub interrupt ( $self, @values ) {
    return $self->[1]->(@values);
}

#----------------------------------------------------------------------

=head1 STANDARD METHODS

These behave as in standard promise implementations:

=over

=item * C<then()>

=item * C<catch()>

=item * C<finally()>

=back

=cut

sub then ( $self, @callbacks ) {
    return ref($self)->new(
        $self->[0]->then(@callbacks),
        $self->[1],
    );
}

sub catch ( $self, @callbacks ) {
    return ref($self)->new(
        $self->[0]->catch(@callbacks),
        $self->[1],
    );
}

sub finally ( $self, @callbacks ) {
    return ref($self)->new(
        $self->[0]->finally(@callbacks),
        $self->[1],
    );
}

1;
