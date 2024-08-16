package Cpanel::Async::InactivityTimer;

# cpanel - Cpanel/Async/InactivityTimer.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::InactivityTimer

=head1 SYNOPSIS

    package My::InactivityTimer;

    use parent 'Cpanel::Async::InactivityTimer';

    sub _TIME_QUERY_OUT($class, $qitem) {
        # … your timeout logic
    }

    sub _GET_NEXT_QUERY_INDEX_AND_ITS_TIMEOUT($class, $queries_hr) {
        # See below.
    }

    #----------------------------------------------------------------------

    package main;

    my $timer = My::InactivityTimer->new(30)->start( \%query_data );

    # To reset the timer, call start() again:

    $timer->start(\%query_data);

    # When we’re done:

    $timer->cancel();

=head1 DESCRIPTION

This module is a base class that implements the core logic of an inactivity
timer. The intended context is a group of parallel queries that work thus:

=over

=item * Queries time out only after a timeout period has passed during
which no activity took place.

=item * No single query times out before that timeout period has elapsed
since the query’s start.

=back

This module assumes use of (and itself uses) L<AnyEvent>.

=head1 SAMPLE WORKFLOW

Given a timeout of 10 seconds:

=over

=item * 0 seconds: Query A starts

=item * 1s: Query B starts

=item * 2s: Query C starts

=item * 8s: Query A’s response arrives. Reset timer: if we get to
18s before another response arrives, B and C (but only they) will time out.
They won’t time out before then.

=item * 13s: Query D starts. This won’t time out until 23s at the
earliest.

=item * 18s: Queries B and C (but B<not> D) time out.

=item * 23s: Query D times out.

=back

=head1 SUBCLASS INTERFACE

Subclasses of this module must implement the following class methods:

=over

=item * C<_TIME_QUERY_OUT($query)> - Time out an individual query.
$query here is a value of the %QUERY_DATA hash passed to C<start()>.
(See below.)

=item* C<_GET_NEXT_QUERY_INDEX_AND_ITS_TIMEOUT(\%QUERY_DATA)> - Returns two
scalars: the index of the next query (i.e., a key from %QUERY_DATA),
and the time left before that individual query should time out.

B<IMPORTANT:> Implementations are responsible for ensuring consistency
between the timeout given to C<new()> and the timeout that this function
returns.

=back

=cut

#----------------------------------------------------------------------

use AnyEvent ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( $TIMEOUT )

Creates a new timer object. This does B<NOT> start the timer itself.

=cut

sub new ( $class, $timeout ) {
    return bless {
        timer   => undef,
        timeout => $timeout,
    }, $class;
}

=head2 $obj = I<OBJ>->start( \%QUERY_DATA )

Starts the timer. Any existing timer will be canceled. The structure of
%QUERY_DATA is left to subclasses to determine.

To facilitate chaining, this returns I<OBJ>.

=cut

sub start ( $self, $query_data_hr ) {

    undef $self->{'timer'};

    my @query_keys = keys %$query_data_hr or do {
        die "$self: No queries!";
    };

    my $timer_sr = \$self->{'timer'};

    my $class = ref $self;

    $$timer_sr = AnyEvent->timer(
        after => $self->{'timeout'},
        cb    => sub {
            undef $$timer_sr;

            for my $qkey (@query_keys) {
                if ( my $query_item = delete $query_data_hr->{$qkey} ) {
                    $class->_TIME_QUERY_OUT($query_item);
                }
            }

            $class->_create_single_timer( $query_data_hr, $timer_sr ) if %$query_data_hr;
        },
    );

    return $self;
}

=head2 $obj = I<OBJ>->cancel()

Cancels any pending timer.

=cut

sub cancel ($self) {
    my $retval = $self->{'timer'} ? 1 : 0;

    undef $self->{'timer'};

    return $retval;
}

#----------------------------------------------------------------------

sub _create_single_timer ( $class, $query_data_hr, $timer_sr ) {    ## no critic qw(ManyArgs) - mis-parse

    my ( $query_idx, $after ) = $class->_GET_NEXT_QUERY_INDEX_AND_ITS_TIMEOUT($query_data_hr);

    # sanity
    $after = 0 if $after < 0;

    $$timer_sr = AnyEvent->timer(
        after => $after,
        cb    => sub {
            undef $$timer_sr;

            if ( my $query_item = delete $query_data_hr->{$query_idx} ) {
                $class->_TIME_QUERY_OUT($query_item);
            }

            $class->_create_single_timer( $query_data_hr, $timer_sr ) if %$query_data_hr;
        },
    );

    return;
}

1;
