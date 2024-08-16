package Cpanel::Async::PromiseTracker;

# cpanel - Cpanel/Async/PromiseTracker.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::PromiseTracker

=head2 SYNOPSIS

    my $tracker = Cpanel::Async::PromiseTracker->new();

    my $new_promise = $tracker->add( $promise1 );
    my $new_promise2 = $tracker->add( $promise2 );

    $tracker->reject_all('armageddon!');

=head1 DESCRIPTION

This module provides a “registry” of pending promises that provides
an “armageddon” workflow to mass-reject all pending promises.

This is useful if, e.g., you have pending CommandStream requests
(cf. L<Cpanel::CommandStream::Server>) and suddenly the transport
layer fails, so you need all pending promises to reject.

=cut

#----------------------------------------------------------------------

use parent qw(Cpanel::Destruct::DestroyDetector);

use Promise::XS ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

=cut

sub new ($class) {
    return bless { _deferred => {} }, $class;
}

=head2 $new_promise = I<OBJ>->add( $OLD_PROMISE )

Adds $OLD_PROMISE to I<OBJ>’s internal cache. If $OLD_PROMISE resolves
or rejects, $new_promise will settle in the same way. If I<OBJ>’s
C<reject_all()> is called before $OLD_PROMISE settles, then $new_promise
will reject with the reason given to C<reject_all()>.

=cut

sub add ( $self, $promise ) {
    my $deferred_hr = $self->{'_deferred'};

    my $d     = Promise::XS::deferred();
    my $d_str = "$d";
    $deferred_hr->{$d_str} = $d;

    $promise->then(
        sub { $d->resolve(@_) },
        sub { $d->reject(@_) },
    )->finally(
        sub {
            delete $deferred_hr->{$d_str};
        }
    );

    return $d->promise();
}

=head2 I<OBJ>->reject_all( $WHY )

Rejects all pending promises with $WHY as the reason.

=cut

sub reject_all ( $self, $reason ) {
    my $deferred_hr = $self->{'_deferred'};

    $_->reject($reason) for values %$deferred_hr;

    %$deferred_hr = ();

    return;
}

1;
