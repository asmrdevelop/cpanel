package Cpanel::PromiseUtils;

# cpanel - Cpanel/PromiseUtils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::PromiseUtils

=head1 SYNOPSIS

    my $ae_promise = _returns_a_promise();

    my $result = Cpanel::PromiseUtils::wait_anyevent($ae_promise);

=head1 DESCRIPTION

This module contains utilities that are useful when dealing with
promises.

=head1 SEE ALSO

L<Promise::XS>, L<Promise::ES6>

=cut

#----------------------------------------------------------------------

use AnyEvent    ();
use Promise::XS ();

use Cpanel::Data::Result ();

# AE freezes its initial internal “now” at compile time,
# which interacts poorly with perlcc because we’ll end up
# with a hard-coded “now” that’s actually a ways past.
# This works around that by ensuring that we reset AE’s “now”
# at runtime, before we use AE.
#
AnyEvent->now_update();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @results = wait_anyevent(@PROMISES)

Loops L<AnyEvent> until all @PROMISES settle (whether they resolve or reject).

Returns a L<Cpanel::Data::Result> for each @PROMISES that indicates
the promise’s settled state: resolved or rejected.

A few sanity-check conveniences are added here:

=over

=item * If @PROMISES is empty an exception is thrown.

=item * If called in scalar context @PROMISES B<MUST> contain only 1 member;
an exception is thrown otherwise.

=item * If called in void context and any @PROMISES reject, an
exception is thrown.

=item * If any @PROMISES resolve or reject with multiple values,
an exception is thrown that reports the problem.
(See L<Promise::XS/AVOID MULTIPLES> for why multiple values are a bad idea.)

=back

=cut

sub wait_anyevent (@promises) {
    if ( !@promises ) {
        local ( $@, $! );
        require Carp;
        Carp::croak('Need >= 1 promise.');
    }

    # This allows void context because void means we don’t care about
    # the result at all. But scalar context when there are multiple promises
    # is more likely to be a mistake.
    if ( !wantarray && defined wantarray && @promises > 1 ) {
        my $how_many = @promises;

        local ( $@, $! );
        require Carp;
        Carp::croak("call in scalar context must receive only 1 promise! (received $how_many)");
    }

    my $cv = AnyEvent->condvar();

    @promises = map { $_->then( \&_create_success, \&_create_failure ); } @promises;

    my @results;

    Promise::XS::all(@promises)->then(
        sub (@results_ars) {
            @results = map { $_->[0] } @results_ars;
            $cv->();
        }
    )->catch(
        sub ($err) {

            # If we got here, then there was a failure in this module,
            # which we should rethrow.
            $cv->croak($err);
        }
    );

    $cv->recv();

    # In void context we want to catch failures here.
    # In other contexts we trust the caller to do that.
    #
    if ( !defined wantarray ) {
        local $Carp::Internal{ +__PACKAGE__ } = 1;

        $_->get() for @results;
    }

    # In list context this is the same as returning @results;
    # in scalar context it’s the same as returning $results[-1].
    # These are both what we want, since in scalar context we already
    # ensured that @results has exactly 1 member.
    #
    return splice @results;
}

sub _create_success ( $result = undef, @extra ) {
    die sprintf( "Promise resolved with %d results ($result @extra); only 1 allowed.", 1 + @extra ) if @extra;

    return Cpanel::Data::Result::create_success($result);
}

sub _create_failure ( $error = undef, @extra ) {
    die sprintf( "Promise rejected with %d results ($error @extra); only 1 allowed.", 1 + @extra ) if @extra;

    return Cpanel::Data::Result::create_failure($error);
}

=head2 $promise = ordered_all($ON_EACH_CR, @PROMISES)

This function runs $ON_EACH_CR for each @PROMISES member’s resolution,
but with a special caveat: no promise is evaluated until its former promise
resolves.

(If any @PROMISES reject, the returned $promise rejects with that
value as well.)

$ON_EACH_CR receives a list of arguments:

=over

=item * a L<Promise::XS::Deferred> that controls the returned $promise

=item * … and whatever the respective @PROMISES member resolved to.

=back

If $ON_EACH_CR either throws or returns a promise that rejects, $promise
will reject accordingly.

If $ON_EACH_CR exhausts the list of @PROMISES with settling the deferred
object, then $promise resolves to nothing.

This is useful if, for example, you’re querying C<foo.bar.baz>, C<foo.bar>,
and C<foo> in parallel but want to check them in a specific order in case
the result from one might preempt the result from another. In this case
you’d probably want to cancel any pending requests.

=cut

sub ordered_all ( $on_each_cr, @promises ) {
    my $d = Promise::XS::deferred();

    sub {
        my $do_next = __SUB__;

        if ( my $this_p = shift @promises ) {
            $this_p->then(
                sub (@res) {
                    my @got = $on_each_cr->( $d, @res );

                    $do_next->() if $d->is_pending();

                    return @got;
                },
            )->catch(
                sub (@err) {
                    $d->reject(@err);
                },
            );
        }
        else {
            $d->resolve();
        }
      }
      ->();

    return $d->promise()->finally(
        sub {
            @promises = ();
        }
    );
}

#----------------------------------------------------------------------

=head2 $promise = delay( $SECONDS )

Returns a promise that resolves (empty) after $SECONDS seconds.
($SECONDS may be an integer or a float.)

=cut

sub delay ($after) {
    my $deferred = Promise::XS::deferred();

    my $t;
    $t = AnyEvent->timer(
        after => $after,
        cb    => sub {
            undef $t;
            $deferred->resolve();
        },
    );

    return $deferred->promise();
}

#----------------------------------------------------------------------

=head2 $promise = retry( $MAKE_PROMISE_CR, $MAX_RETRIES [, $SHOULD_RETRY_CR] )

This function simplifies the task of retrying a promise-returning operation.

It takes 2 or 3 args:

=over

=item * A coderef that returns a promise.

=item * The max # of retries.

=item * OPTIONAL: A coderef that catches the promise failure and returns
a boolean to indicate whether to retry. If not given, we’ll always retry
until the max # is hit or until a success.

=back

For example, let’s say you want to retry if the error mentions the word
C<sunshine>, up to 50 times. That looks like this:

    my $retrying_promise = Cpanel::PromiseUtils::retry(
        \&_promise_returning_function,
        50,
        sub ($err) { $err =~ m<sunshine> },
    );

=cut

sub retry ( $promise_cr, $max_retries, $should_retry_cr = undef ) {    ## no critic qw(ManyArgs) - mis-parse
    my $retries = 0;

    return $promise_cr->($retries)->catch(
        sub ($why) {
            my $currentsub = __SUB__;

            if ( $retries < $max_retries ) {
                my $should_retry;

                if ($should_retry_cr) {
                    local $@;
                    eval { $should_retry = $should_retry_cr->($why); 1 } or do {
                        warn "Failed to determine if I should retry (assuming no): $@";
                    };
                }
                else {
                    $should_retry = 1;
                }

                if ($should_retry) {
                    $retries++;
                    return $promise_cr->($retries)->catch($currentsub);
                }
            }

            return Promise::XS::rejected($why);
        }
    );
}

1;
