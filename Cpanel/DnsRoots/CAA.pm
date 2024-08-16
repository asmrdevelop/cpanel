package Cpanel::DnsRoots::CAA;

# cpanel - Cpanel/DnsRoots/CAA.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsRoots::CAA

=head1 DESCRIPTION

This module contains logic for querying public DNS to match domains against
CAA strings.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::DNS::Client            ();
use Cpanel::DnsRoots::ErrorWarning ();
use Cpanel::DnsUtils::CAA          ();
use Cpanel::Set                    ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $forbiddances_ar = get_forbiddance_promises( $RESOLVER, \@CAA_STRINGS, \@DOMAINS )

This queries public DNS to determine whether a given certificate authority
(CA) is authorized to issue SSL certificates for given @DOMAINS.

$RESOLVER is a L<Cpanel::DNS::Unbound::Async> instance.

@CAA_STRINGS is the set of CAA strings that a particular CA recognizes
as authorization to issue an SSL certificate for the domain.

The return is a reference to an array of promises, one per @DOMAINS.
Each promise always resolves; failures are reported via C<warn()> but
otherwise treated the same as if no CAA record exists.

Each returned promise’s resolution will be one of:

=over

=item * undef, to indicate that we didn’t find a CAA record that prevents
the CA from issuing SSL certificates for the domain. (NB: This includes
the case of failures.)

=item * an array reference, to indicate that the CA is B<forbidden>
from issuing SSL certificates for the domain. Members are:

=over

=item * 0) The DNS name of the RRSET that indicates the forbiddance.
This will either be the domain itself or one of its parent domains.

=item * 1) The canonical name (CNAME) of the RRSET described above.
If there is no CNAME—there usually won’t be—this will be undef.

=back

=back

=cut

sub get_forbiddance_promises ( $resolver, $caa_strings_ar, $domains_ar ) {    ## no critic qw(ManyArgs) - mis-parse
    my @return_promises;

    # This cache prevents creating multiple promises for the same domain
    # when there are subdomains involved. For example, if we look up
    # both “example.com” and “foo.example.com”, without this cache we’d
    # have two separate promises for “example.com”. It doesn’t produce two
    # separate _queries_, at least, because $resolver caches its lookup
    # results, but even so it’s beneficial to minimize the number of
    # promises that we create.
    my %domain_caa_promise;

    for my $domain (@$domains_ar) {
        push @return_promises, _get_forbiddance_promise( $resolver, $caa_strings_ar, $domain, \%domain_caa_promise );
    }

    return \@return_promises;
}

sub _get_forbiddance_promise ( $resolver, $caa_strings_ar, $domain, $domain_caa_promise_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    my @possible_caa_owners = Cpanel::DNS::Client::get_possible_registered_or_tld($domain);

    my %owner_promise = map {
        my $name = $_;

        $domain_caa_promise_hr->{$name} ||= $resolver->ask( $name, 'CAA' )->catch(
            Cpanel::DnsRoots::ErrorWarning::create_dns_query_promise_catcher( $name, 'CAA' ),
        );

        my $promise = $domain_caa_promise_hr->{$name};

        ( $name => $promise );
    } @possible_caa_owners;

    my $first_domain = shift @possible_caa_owners or do {
        die "“$domain”: CAA ownership logic error!";
    };

    return $owner_promise{$first_domain}->then(
        sub ($real_qresult) {
            if ($real_qresult) {
                my $records_ar = $real_qresult->decoded_data();

                if (@$records_ar) {

                    # Case: CAA records found.
                    return [
                        $real_qresult->{'qname'},
                        $real_qresult->{'canonname'},
                        $records_ar,
                    ];
                }
            }

            if ( my $next = shift @possible_caa_owners ) {

                # Case: Current query came up empty, but there are
                # still non-TLD parent domains to try.
                return $owner_promise{$next}->then(__SUB__);
            }

            # Case: Current query came up empty, and this was the last
            # non-TLD parent of $domain.
            return [];
        },
    )->then(
        _get_final_promise_parser( $caa_strings_ar, $domain ),
    );
}

sub _get_final_promise_parser ( $caa_strings_ar, $domain ) {
    return sub ($qresult_ar) {
        my ( $rrset_owner, $rrset_cname, $records_ar ) = @$qresult_ar;

        my $is_allowed = !$records_ar || do {
            my $allowed_cas;

            if ( 0 == rindex( $domain, '*.', 0 ) ) {
                $allowed_cas = Cpanel::DnsUtils::CAA::get_accepted_wildcard_issuers( $caa_strings_ar, $records_ar );
            }
            else {
                $allowed_cas = Cpanel::DnsUtils::CAA::get_accepted_non_wildcard_issuers( $caa_strings_ar, $records_ar );
            }

            Cpanel::Set::intersection(
                $allowed_cas,
                $caa_strings_ar,
            );
        };

        return $is_allowed ? undef : [ $rrset_owner, $rrset_cname ];
    };
}

1;
