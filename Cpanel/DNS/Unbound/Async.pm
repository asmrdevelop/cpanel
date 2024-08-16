package Cpanel::DNS::Unbound::Async;

# cpanel - Cpanel/DNS/Unbound/Async.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 Cpanel::DNS::Unbound::Async

Cpanel::DNS::Unbound::Async - Asynchronous wrapper around L<DNS::Unbound>

=head1 SYNOPSIS

    my $dns = Cpanel::DNS::Unbound::Async->new();

    my @promises = (
        $dns->ask('cpanel.net', 'NS', 10)->then( … ),
        $dns->ask('perl.com', 'NS', 10)->then( … ),
    );

    my $cv = AnyEvent->condvar();

    Promise::ES6->all( \@promises )->finally($cv);

    $cv->recv();

=head1 DESCRIPTION

This module “cPanel-izes” L<DNS::Unbound> by applying timeout logic as well
as L<Cpanel::Exception> rejections for timeouts and failure responses.

This module assumes use of L<AnyEvent>.

=head1 TIMEOUTS

Executing many DNS queries concurrently trips rate limiting for
some servers. Thus, a single query that would normally be quick might take
much, much longer when there are other queries going in parallel. For that
reason, we can’t use a simple per-query timeout here; instead we implement
an inactivity timeout via L<Cpanel::Async::InactivityTimer>.

=head1 SEE ALSO

The major difference between this module and L<Cpanel::DNS::Unbound> is that,
while the other module exposes a number of functions that block and
return results directly, this module exposes a single query
function—the C<ask()> method—which returns a promise. You can thus easily
build concurrent queries this way, or even combine DNS queries with
other network operations like HTTP requests.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

use AnyEvent     ();
use DNS::Unbound ();
use Promise::ES6 ();

use Cpanel::Config::LoadCpConf         ();
use Cpanel::DNS::Unbound::Async::Timer ();
use Cpanel::DNS::Unbound::Async::Query ();
use Cpanel::Autodie                    ();
use Cpanel::DNS::Rcodes                ();
use Cpanel::DNS::Unbound::Result       ();
use Cpanel::DNS::Unbound::Singleton    ();
use Cpanel::Exception                  ();
use Cpanel::Promise::Interruptible     ();
use Cpanel::TempFH                     ();

use constant {
    _INACTIVITY_TIMEOUT => 30,

    # Hard-code this for now; make it adjustable later if needed.
    _UB_DEBUGLEVEL => 2,

    _IGNORE_RCODE => {
        3 => 1,    # NXDOMAIN,
    },

    _DEBUG => 0,

    _QUERY_IS_NOT_CANCELED => 1,
    _QUERY_IS_CANCELED     => 0,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class.

$obj will use the result of
C<Cpanel::DNS::Unbound::Singleton::get()> internally to run queries.

=cut

sub new ($class) {

    my $ub = Cpanel::DNS::Unbound::Singleton::get();

    my %query_data;
    my $timer = Cpanel::DNS::Unbound::Async::Timer->new( $class->_INACTIVITY_TIMEOUT() );

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    my $self = {
        pid         => $$,
        ub          => $ub,
        query_data  => \%query_data,
        timer       => $timer,
        query_queue => [],
        pool_size   => $cpconf->{'dns_recursive_query_pool_size'},
    };

    AnyEvent->now_update();

    $self->{'watcher'} = AnyEvent->io(
        fh   => $ub->fd(),
        poll => 'r',

        # NOTE: It’s essential that this callback not refer to $self,
        # or we’ll have a memory leak.
        cb => sub {
            $ub->process();

            # Since we just got a query result, we need to reset the timer.
            #
            # We delete the old timer, *then* create the new one.
            #
            # (If we just did a simple assignment, we’d create the new one
            # before deleting the old.)

            $timer->start( \%query_data ) if %query_data;
        },
    );

    return bless $self, $class;
}

#----------------------------------------------------------------------

=head2 promise($result) = I<OBJ>->ask( $QNAME, $QTYPE )

Creates a new DNS query of the given $QNAME and $QTYPE (e.g., C<NS>).

The return is a L<Cpanel::Promise::Interruptible> instance. That promise’s
resolution is a L<Cpanel::DNS::Unbound::Result> instance, and its rejection
is an instance of either L<Cpanel::Exception> or L<DNS::Unbound::X>.
Calling C<interrupt()> on a promise in the chain cancels the pending query.

Note that this considers most DNS-level errors (e.g., rcode=C<SERVFAIL>) to
be failures. The only exemption is L<NXDOMAIN>, which is treated as a
success. (You can still distinguish the two cases, of course, by querying
the result object.)

=cut

sub ask ( $self, $qname, $qtype ) {

    my $pool_size = $self->{'pool_size'};

    if ( $pool_size && $pool_size <= $self->count_pending_queries() ) {
        my $is_alive_sr;

        my $plain_p = Promise::ES6->new(
            sub ( $res, $rej ) {

                # The last member of @queue_item is a boolean that
                # indicates whether the caller still wants the query result.
                # If the promise’s cancel() is called, that boolean
                # becomes falsy. Thus, when the queue processor logic
                # examines @queue_item, it’ll see the now-falsy value and
                # skip the request.

                my @queue_item = ( $qname, $qtype, $res, $rej, _QUERY_IS_NOT_CANCELED );
                push @{ $self->{'query_queue'} }, \@queue_item;

                $is_alive_sr = \$queue_item[-1];
            }
        );

        return Cpanel::Promise::Interruptible->new(
            $plain_p,
            sub {
                if ( ref $$is_alive_sr ) {

                    # We get here if:
                    #   1. The initial request went into the queue instead
                    #      of firing right away.
                    #   2. The request subsequently fired.
                    #   3. *THEN*, the caller interrupt()ed the request.

                    $$is_alive_sr->interrupt();
                }
                else {

                    # We get here if the caller calls interrupt()
                    # before the request ever fires.

                    $$is_alive_sr = _QUERY_IS_CANCELED;
                    _DEBUG && print STDERR "* skip: $qname/$qtype\n";
                }
            },
        );
    }

    return $self->_ask_non_queue( $qname, $qtype );
}

sub _NOOP { return }

sub _ask_non_queue ( $self, $qname, $qtype ) {
    my $ub = $self->{'ub'};

    _DEBUG && print STDERR "asking: $qname/$qtype\n";

    my $ub_promise = $self->{'ub'}->resolve_async( $qname, $qtype );

    my $reject_cr;

    my $new_promise_str;
    my $query_data_hr = $self->{'query_data'};

    my $after_this_cr = sub {

        # The Timer object should take care of this, but just in case:
        delete $query_data_hr->{$new_promise_str};

        while ( @{ $self->{'query_queue'} } ) {
            my $next_ar = shift @{ $self->{'query_queue'} };

            my ( $qname, $qtype, $res, $rej, $state ) = @$next_ar;

            next if $state == _QUERY_IS_CANCELED;

            my $interruptible_p = $self->_ask_non_queue( $qname, $qtype )->then( $res, $rej );

            $next_ar->[-1] = $interruptible_p;

            last;
        }
    };

    my $new_promise = Cpanel::Promise::Interruptible->new(
        Promise::ES6->new(
            sub ( $res, $rej ) {
                $reject_cr = $rej;
                $ub_promise->then( $res, $rej );
            }
        ),
        sub {
            _DEBUG && print STDERR "* stop: $qname/$qtype\n";

            delete $query_data_hr->{$new_promise_str};

            $ub_promise->cancel();

            $after_this_cr->();
        },
    );

    $new_promise_str = "$new_promise";

    my $is_first_query = !%$query_data_hr;

    $query_data_hr->{$new_promise_str} = Cpanel::DNS::Unbound::Async::Query->new(
        'rejector'             => $reject_cr,
        'qname'                => $qname,
        'qtype'                => $qtype,
        'dns_unbound_promise'  => $ub_promise,
        'minimum_timeout_time' => ( $self->_INACTIVITY_TIMEOUT() + AnyEvent->time() )
    );

    $new_promise->finally(
        sub {
            _DEBUG && print STDERR "> done: $qname/$qtype\n";

            $after_this_cr->();
        },
    )->catch( \&_NOOP );

    # It’s important that we NOT reset an existing timer here.
    #
    # Example:
    #   Query A starts at 0 seconds.
    #   Query B starts at 29 seconds.
    #
    # We need to time out query A at the 30-second mark, but that
    # won’t happen if we’ve just reset the timeout. Thus, only when
    # the query is the *first* one should we reset/create the timer.
    #
    if ($is_first_query) {
        $self->{'timer'}->start($query_data_hr);
    }

    return $new_promise->then(
        sub ($got) {
            _analyze_dns_unbound_result_for_error( $qname, $qtype, $got );

            Cpanel::DNS::Unbound::Result::convert($got);

            return $got;
        }
    );
}

#----------------------------------------------------------------------

=head2 $count = I<OBJ>->count_pending_queries()

Returns the number of I<OBJ>’s pending queries.

=cut

sub count_pending_queries ($self) {
    return 0 + keys %{ $self->{'query_data'} };
}

#----------------------------------------------------------------------

sub DESTROY ($self) {
    $self->SUPER::DESTROY() if $$ == $self->{'pid'};
    return;
}

sub _analyze_dns_unbound_result_for_error ( $qname, $qtype, $result ) {
    my $rcode = $result->{'rcode'};

    if ( !@{ $result->{'data'} } ) {

        # We quietly ignore NXDOMAIN, but other failure-state
        # rcodes are an error.
        if ( $rcode > 0 && !_IGNORE_RCODE()->{$rcode} ) {
            die Cpanel::Exception::create( 'DNS::ErrorResponse', [ result => $result ] );
        }
    }

    # This seems like it’ll be pretty edge-case-y:
    elsif ( $rcode > 0 ) {
        my $code_txt = Cpanel::DNS::Rcodes::RCODE()->[$rcode];
        warn "DNS query ($qname, $qtype) gave result but indicated error: $code_txt\n";
    }

    return;
}

1;
