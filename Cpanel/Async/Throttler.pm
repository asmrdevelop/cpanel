package Cpanel::Async::Throttler;

# cpanel - Cpanel/Async/Throttler.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 DESCRIPTION

This class provides reusable logic to limit the number of concurrent promises.

=head1 WORKFLOW

Each time a job is C<add()>ed to an instance of this class, that instance will
check to see if it already has its maximum number of concurrent promises. If
so, then the new job is added to an internal queue; otherwise, the job runs
immediately.

Each time a job ends, the next-queued item in the internal queue, if any, runs.

This workflow continues until all jobs have run.

=cut

#----------------------------------------------------------------------

use Promise::XS ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $MAX_ACTIVE_PROMISES )

Instantiates I<CLASS>.

=cut

sub new ( $class, $size ) {
    return bless {
        max     => $size,
        pending => [],
        active  => 0,
    }, $class;
}

=head2 $promise = I<OBJ>->add( $CODEREF )

Adds a job to I<OBJ>’s queue. $CODEREF must return a promise.

(NB: That promise B<MUST> finish at some point, or else the throttler
will never dequeue it. If that happens enough times the throttler will
hang. So take care if using, e.g., L<Cpanel::Promise::Interruptible>!)

The return is itself a promise that resolves or rejects with the same
status as what $CODEREF returns.

=cut

sub add ( $self, $cr ) {
    my $d = Promise::XS::deferred();

    if ( $self->{'active'} == $self->{'max'} ) {
        push @{ $self->{'pending'} }, [ $d, $cr ];
    }
    else {
        _run( $d, $cr, $self->{'pending'}, \$self->{'active'} );
    }

    return $d->promise();
}

sub _run ( $d, $cr, $pending_ar, $active_sr ) {    ## no critic qw(ManyArgs) - mis-parse
    $$active_sr++;

    $cr->()->then(
        sub { $d->resolve(@_) },
        sub { $d->reject(@_) },
    )->finally(
        sub {
            $$active_sr--;

            if ( my $next_d_and_cr = shift @$pending_ar ) {
                _run( @$next_d_and_cr, $pending_ar, $active_sr );
            }
        }
    );

    return;
}

1;
