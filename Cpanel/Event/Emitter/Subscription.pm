package Cpanel::Event::Emitter::Subscription;

# cpanel - Cpanel/Event/Emitter/Subscription.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Event::Emitter::Subscription - The right thing, simplified!

=head1 SYNOPSIS

    {
        my $ss = $emitter->create_subscription( message => $cb );

        # $cb will now fire on any “message” event.
    }

    # $cb will no longer fire on “message” events.

=head1 DESCRIPTION

L<Cpanel::Event::Emitter> instantiates this class as a means of simplifying
unsubscriptions.

Consider:

    {
        my $cb = sub { print shift };
        $emitter->on( message => $cb );

        # … do other stuff

        $emitter->off( message => $cb );
    }

In the above example, if an exception happens between calls to C<on()> and
C<off()>, the callback will never be unregistered. This is, in effect,
an action-at-a-distance bug: a locally-scoped change to C<$emitter> will be
in effect until C<$emitter> is garbage-collected.

Even if there’s no exception, the fact that the call to C<off()> is required
requires more work to do the right thing than to do the wrong thing (i.e., to
neglect to unregister the callback).

The present class facilitates an alternative semantic:

    {
        my $ss = $emitter->create_subscription( message => $cb );

        # … do other stuff
    }

In the above code, C<$ss> is an instance of this class. When that object
is C<DESTROY()>ed, the callback is automatically unregistered from C<$emitter>.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $EMITTER, $EVENT_NAME, $CALLBACK )

Instantiates this class. $EMITTER is an instance of
L<Cpanel::Event::Emitter> (or some other compatible class).

$EVENT_NAME and $CALLBACK are given to the $EMITTER’s C<on()> method.

=cut

sub new ( $class, $emitter, $evt_name, $cb ) {
    $emitter->on( $evt_name, $cb );

    my @self = ( $emitter, $evt_name, $cb );

    return bless \@self, $class;
}

sub DESTROY ($self) {
    $self->SUPER::DESTROY();

    $self->[0]->off( @{$self}[ 1, 2 ] );

    return;
}

1;
