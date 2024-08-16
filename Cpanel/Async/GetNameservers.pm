package Cpanel::Async::GetNameservers;

# cpanel - Cpanel/Async/GetNameservers.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::GetNameservers

=head1 SYNOPSIS

    my $unbound = Cpanel::DNS::Unbound::Async->new();

    my $promise = Cpanel::Async::GetNameservers::for_domain($unbound, 'x.org');

    $promise->then(
        sub ($nameservers_ar) {
            print "nameserver: $_\n" for @$nameservers_ar;
        },
    );

=head1 DESCRIPTION

This module implements asynchronous nameserver-lookup logic using
L<Cpanel::DNS::Unbound::Async>.

=cut

#----------------------------------------------------------------------

use Promise::XS ();

use Cpanel::DNS::Client            ();
use Cpanel::DnsRoots::ErrorWarning ();
use Cpanel::PromiseUtils           ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise($nss) = for_domain( $UNBOUND, $DOMAIN )

Using the given $UNBOUND (instance of L<Cpanel::DNS::Unbound::Async>),
fetches the $DOMAIN’s authoritative nameservers, falling back to
parent domains until we find a registered domain with authoritative
nameservers.

For example, C<foo.cpanel.net> will yield C<cpanel.net>’s nameservers
as long as C<foo.cpanel.net> doesn’t have its own authoritative nameservers.

On a query error or timeout, this function will C<warn()> and discard the
result.

One-liner to demonstrate functionality:

    perl -w -Mstrict -MCpanel::PromiseUtils -MCpanel::Async::GetNameservers -MCpanel::DNS::Unbound::Async -e'my $dns = Cpanel::DNS::Unbound::Async->new(); my $p = Cpanel::Async::GetNameservers::for_domain($dns, "e.d.5.2.0.0.0.0.c.0.0.b.e.c.a.f.3.8.0.0.1.1.1.f.0.8.8.2.3.0.a.2.ip6.arpa")->then( sub { print "ns: $_\n" for @{ shift() } } ); Cpanel::PromiseUtils::wait_anyevent($p)'

This is an async equivalent to L<Cpanel::DNS::Unbound>’s
C<get_nameservers_for_domain()> and C<get_nameservers_for_domains()>.

=cut

sub for_domain ( $unbound, $domain ) {
    my @maybe_registered = Cpanel::DNS::Client::get_possible_registered($domain);

    # Launch all queries in parallel, but process results in descending
    # length order of the queried name.

    my %pending_index;
    @pending_index{ 0 .. $#maybe_registered } = ();

    my @promises;

    for my $i ( 0 .. $#maybe_registered ) {
        my $name = $maybe_registered[$i];

        my @query = ( $name, 'NS' );

        push @promises, $unbound->ask(@query)->catch(
            Cpanel::DnsRoots::ErrorWarning::create_dns_query_promise_catcher(@query),
        )->finally(
            sub { delete $pending_index{$i} },
        );
    }

    my @nss;

    return Cpanel::PromiseUtils::ordered_all(
        sub ( $deferred, $result ) {

            # $result will be undef if the query failed.
            if ($result) {
                if ( @nss = @{ $result->decoded_data() } ) {
                    $deferred->resolve();
                }
            }
        },
        @promises,
    )->finally(
        sub {
            $_->interrupt() for @promises[ keys %pending_index ];
        },
    )->then(
        sub { \@nss },
    );
}

1;
