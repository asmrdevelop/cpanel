package Cpanel::DnsRoots::DomainManagement;

# cpanel - Cpanel/DnsRoots/DomainManagement.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsRoots::DomainManagement

=head1 SYNOPSIS

    my $promises_ar = Cpanel::DnsRoots::DomainManagement::are_domains_managed(
        $resolver,
        [ 'my.example.com' ],
    );

    $promises_ar->[0]->then( sub($result) {
        if ($result) {
            # yay! “my.example.com” is managed.
        }
        else {
            # oops! DNS doesn’t have an authoritative nameserver
            # for that domain.
        }
    } );

=head1 DESCRIPTION

This module implements a check to see if DNS has any functional
authoritative nameservers for a given domain.

Note the distinction between this check—which requires a functional
authoritative nameserver to pass—and a “domain registration” check,
which passes even without a functional nameserver. Any “managed” domain
is registered, but not every registered domain is necessarily “managed”.

=head1 SEE ALSO

If you need a pure “domain registration” check, inclusive of cases
where the registrar’s configured authoritative nameserver for the domain
doesn’t (yet?) actually serve DNS for the domain, look at
L<Cpanel::DNS::GetNameservers>.

=cut

#----------------------------------------------------------------------

use Promise::ES6 ();

use Cpanel::DNS::Client            ();
use Cpanel::DnsRoots::ErrorWarning ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $promises = are_domains_managed( $RESOLVER, \@DOMAINS )

This function determines, for each of @DOMAINS, whether DNS reports that
the given domain or any of its parent domains has at least one
authoritative nameserver. Whether those nameservers are the domain’s or are
those for a registered parent domain (and I<which> registered domain) is not
defined.

This function is thus mostly useful merely for determining whether
a domain is managed (i.e., registered with a properly configured
authoritative nameserver) or not.

$RESOLVER is an instance of L<Cpanel::DNS::Unbound::Async>.

This returns a reference to an array of promises, one for each @DOMAINS.
Each promise resolves to the L<Cpanel::DNS::Unbound::Result> instance for
the query that returned the NS result, or undef if the domain has no
managing nameservers.

All failures are treated as nonfatal, so the returned promise
will always resolve.

=head3 Edge-case note

In some cases (e.g., the C<.lk> TLD) there exist registered domains
whose authoritative nameservers return empty in response to NS queries.
Regardless of whether this is a correct configuration, we can at least
infer from it that the domain in question is registered.

In these cases it’s important to distinguish
between NXDOMAIN—which doesn’t indicate management—and an empty response,
which indicates that the nameserver recognizes the given name, but just
lacks an NS record for it.

=cut

sub are_domains_managed ( $resolver, $domains_ar ) {
    my @promises = map { _is_domain_managed( $resolver, $_ ) } @$domains_ar;

    return \@promises;
}

sub _give_undef {
    return undef;
}

sub _is_domain_managed ( $resolver, $domain ) {

    # NB: A true “get_manager_nameservers” function would do something
    # akin to what CAA checks do: query $DOMAIN, then its parent domain,
    # then the next parent domain, etc., until we either get a result or
    # reach a TLD. See Cpanel::DnsRoots::CAA for such logic.

    my @possible_ns_owners = Cpanel::DNS::Client::get_possible_registered_or_tld($domain);

    my %owner_promise;

    my $resolving_name = q<>;

    return Promise::ES6->new(
        sub ( $res, $rej ) {

            for my $name (@possible_ns_owners) {
                my $this_name = $name;

                my $query_p = $resolver->ask( $name, 'NS' );

                $query_p->catch( Cpanel::DnsRoots::ErrorWarning::create_dns_query_promise_catcher( $name, 'NS' ) );

                # We want to treat all errors as nonfatal:
                $owner_promise{$name} = $query_p->then(
                    sub ($result) {
                        if ( !$resolving_name ) {
                            if ( !$result->nxdomain() ) {
                                $resolving_name = $name;
                                $res->($result);
                            }
                        }
                    },

                    # We’ll already have warn()ed about the error.
                    # This is here just to make the promise resolve.
                    \&_give_undef,
                );
            }

            # This is in a separate loop because the tests
            # use synchronous queries.
            for my $name (@possible_ns_owners) {
                my $this_name = $name;

                $owner_promise{$name}->finally(
                    sub {
                        delete $owner_promise{$this_name};

                        if ( !$resolving_name && !%owner_promise ) {
                            $res->(undef);
                        }
                    }
                );
            }
        }
    )->finally(
        sub {
            delete $owner_promise{$resolving_name};

            $_->interrupt() for values %owner_promise;
            %owner_promise = ();
        }
    );
}

1;
