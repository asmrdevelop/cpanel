package Cpanel::DNS::Unbound::Async::Query;

# cpanel - Cpanel/DNS/Unbound/Async/Query.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DNS::Unbound::Async::Query - An object class to represent an Async L<Cpanel::DNS::Unbound> query.

=head1 SYNOPSIS

    $query_data_hr->{$new_promise_str} = Cpanel::DNS::Unbound::Async::Query->new(
        'rejector'             => $reject_cr,
        'qname'                => $qname,
        'qtype'                => $qtype,
        'dns_unbound_promise'  => $ub_promise,
        'minimum_timeout_time' => ( $self->_INACTIVITY_TIMEOUT() + AnyEvent->time() )
    );

=head1 ACCESSORS

The following are all read-only:

=head2 rejector()

A code ref that will reject the dns query that L<Cpanel::DNS::Unbound::Async>
returns.

=head2 qname()

The query name.  Ex: C<cpanel.net>

=head2 qtype()

The query type.  Ex: C<AAAA>

=head2 dns_unbound_promise()

The DNS::Unbound promise. This is I<not> the same promise as what
the C<rejector()> rejects; this is what L<DNS::Unbound> gives us.

=head2 minimum_timeout_time()

The minium timeout time (inactivity timeout), as an epoch timestamp.

=cut

use Class::XSAccessor (
    constructor => 'new',
    getters     => [
        qw(
          rejector
          qname
          qtype
          dns_unbound_promise
          minimum_timeout_time
        )
    ]
);

1;
