package Cpanel::SSL::DCV::DNS;

# cpanel - Cpanel/SSL/DCV/DNS.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::DNS - DNS-based DCV logic

=head1 SYNOPSIS

    my $results_hr = Cpanel::SSL::DCV::DNS::check_multiple_nonfatal(
        queries => {
            '_the-dcv-name.example.com' => [ 'TXT', 'the-expected-value' ],
        },
        ancestor_obj => ..,     #optional
    );

=head1 DESCRIPTION

This is the core module for DNS DCV.

There are two workflows for DNS DCV:

=head2 Workflow 1: Per-user

In per-user DNS DCV, you should not use this module; instead,
look at L<Cpanel::SSL::DCV::DNS::User> or L<Cpanel::SSL::DCV::DNS::Root>.

=head2 Workflow 2: Combined

In a combined DNS DCV, you’ll interact with this module
as well as L<Cpanel::SSL::DCV::DNS::Setup>.

The steps are:

=over

=item 1) Run this module’s C<get_mutex_and_domain_dcv_zones()> for
each user’s domains. Hold onto the mutexes and zone lists as well
as each user’s domains.

=item 2) Assemble a single array of all zones returned from step 1, then
call C<Cpanel::SSL::DCV::DNS::Setup::set_up_for_zones()> on that array.

=item 3) Run this module’s C<finish_dns_dcv()> function, using the
returned values from step 2 as well as the full lists of zones and domains.
As you iterate back through each user’s domains, you’ll reference the
returned L<Cpanel::SSL::DCV::DNS::Result> instance to determine DNS DCV
state.

=back

=cut

use Try::Tiny;

use Cpanel::Config::LoadCpConf       ();
use Cpanel::Context                  ();
use Cpanel::DnsUtils::Name           ();
use Cpanel::Exception                ();
use Cpanel::LocaleString             ();
use Cpanel::SSL::DCV::DNS::Constants ();
use Cpanel::SSL::DCV::DNS::Mutex     ();
use Cpanel::SSL::DCV::DNS::Result    ();
use Cpanel::TimeHiRes                ();
use Cpanel::UserZones::User          ();
use Cpanel::DnsRoots                 ();

=head1 FUNCTIONS

=head2 check_multiple_nonfatal( %OPTS )

This implements the check part of DCV. It won’t alter DNS.

As the name imples, no exception is thrown on DCV failure.
(An exception B<is> thrown if the actual query fails.)

%OPTS is:

=over

=item * C<queries> - Hash reference. Keys are the name to query, and values
are two-member arrays: query type (e.g., C<TXT>) and expected value.

=item * C<ancestor_obj> - Optional, an instance of
L<Cpanel::SSL::DCV::AnyAncestor>. If given, the object will be updated on
each success/failure and used to forgo redundant subdomain DCV checks.

B<IMPORTANT:> This assumes that each query name is a single leaf label
followed by a domain that is being DCVed. (That assumption is valid
at least for Comodo as well as cPanel’s local DNS DCV.)

=back

This goes through C<queries> and reports its results in a returned hash
reference. The hash reference’s keys are the query names, and the values
are hash references:

=over

=item C<query_results> - (arrayref or undef) The strings that the DNS query
returned. This will be undef if C<ancestor_obj> is given and there
was no need to query the corresponding DNS name.

=item C<succeeded> - Boolean. Will be truthy if DCV against the query name
succeeded or if C<ancestor_obj> validates a domain that we didn’t test
directly.

=item C<failure_reason> - undef or nonexistent on success; on failure
this will be a L<Cpanel::LocaleString> instance.

=back

This will rerun the queries for a while to allow time for DNS propagation.

=cut

sub check_multiple_nonfatal {
    my %opts = @_;

    my $queries_hr = $opts{'queries'} or die 'need “queries”';

    my $ancestor_obj = $opts{'ancestor_obj'};

    my $res = Cpanel::DnsRoots->new()->get_resolver();

    my %queries_left = %$queries_hr;

    my %result;

    my $start  = Cpanel::TimeHiRes::time();
    my $finish = $start + _get_dns_dcv_timeout();

    while ( %queries_left && ( Cpanel::TimeHiRes::time() < $finish ) ) {

        # Walk through the names in sorted order so that we can capitalize on
        # ancestor DCV.
        my @name_qtypes;
        for my $queried_name ( sort { length $a <=> length $b } keys %queries_left ) {
            my ( $qtype, $value ) = @{ $queries_left{$queried_name} };

            push @name_qtypes, [ $queried_name, $qtype ];
        }

        $res->forget_cached_results();
        my $ret = _do_recursive_queries( $res, \@name_qtypes );

        foreach my $query (@name_qtypes) {
            my $query_result = shift @$ret;
            my ( $queried_name, $qtype ) = @$query;
            my $value = $queries_left{$queried_name}->[1];

            my ($domain) = substr( $queried_name, 1 + index( $queried_name, '.' ) );

            if ($ancestor_obj) {
                if ( my $authz_dom = $ancestor_obj->get_authz_domain($domain) ) {
                    delete $queries_left{$queried_name};

                    $result{$queried_name} = {
                        succeeded     => 1,
                        query_results => undef,
                    };

                    next;
                }
            }

            my $data_ar = $query_result->{'decoded_data'};
            $data_ar ||= $query_result->{result}{data};

            # See COBRA-10033 which will allow us to avoid _dcv_sleep();
            my @got = $data_ar ? @$data_ar : ();

            my $succeeded = ( grep { length $_ && $_ eq $value } @got ) && 1;

            #We can only stop checking if we get a success.
            #A non-success isn’t necessarily a failure since the
            #DNS zone update might just need more time to propagate.
            if ($succeeded) {
                delete $queries_left{$queried_name};

                if ($ancestor_obj) {
                    $ancestor_obj->add_validated_domain($domain);
                }
            }

            $result{$queried_name} = {
                query_results => \@got,
                succeeded     => $succeeded,
                ( $succeeded ? () : ( failure_reason => Cpanel::LocaleString->new( 'The [asis,DNS] query to “[_1]” for the [asis,DCV] challenge returned no “[_2]” record that matches the value “[_3]”.', $queried_name, $qtype, $value ) ) ),
            };
        }

        last if !%queries_left;

        _dcv_sleep();
    }

    return \%result;
}

#----------------------------------------------------------------------

=head2 ($mutex_obj, $domain_zone_hr) = get_mutex_and_domain_dcv_zones($USERNAME, \@DOMAINS)

Takes a $USERNAME and a list of @DOMAINS.

Returns two items:

=over

=item * A L<Cpanel::SSL::DCV::DNS::Mutex> instance for $username.
It follows that such an object must not already exist; this limitation
is by design, so please don’t try to defeat it.

=item * A lookup hash reference whose keys are the zones used for
DNS DCV on @DOMAINS.

=back

Note that a hash between @DOMAINS and the returned zones is not given.
Use C<Cpanel::DnsUtils::Name::get_longest_short_match()> for this lookup.

=cut

sub get_mutex_and_domain_dcv_zones ( $username, $domains_ar ) {
    Cpanel::Context::must_be_list();

    return (
        Cpanel::SSL::DCV::DNS::Mutex->new($username),
        _get_dcv_zones( $username, $domains_ar ),
    );
}

#----------------------------------------------------------------------
# This is the base logic for DNS DCV that implements the ancestor domain
# optimization described in the ::User submodule.
#
# Called from the ::Root and ::User submodules.

sub _verify_domains {
    my ( $install_cr, %OPTS ) = @_;

    if ( !@{ $OPTS{'domains'} } ) {
        die 'Need at least 1 “domains”!';
    }

    my $username = $OPTS{'username'} or die 'need “username”';

    my $mutex = Cpanel::SSL::DCV::DNS::Mutex->new($username);

    my $dns_dcv_zones_ar = _get_dcv_zones( $username, $OPTS{'domains'} );

    my ( $value, $state ) = $install_cr->($dns_dcv_zones_ar);

    my %altered_zones = ref $state && $state->{'zones_modified'} ? ( map { $_ => 1 } @{ $state->{'zones_modified'} } ) : ();

    my @zones_that_failed_to_be_altered = grep { !$altered_zones{$_} } @$dns_dcv_zones_ar;

    for my $zone (@zones_that_failed_to_be_altered) {

        # Alter failed, skip testing this one
        warn "Failed to modify $zone";

        # We used to populate %zone_result here, but now that
        # happens in Cpanel::SSL::DCV::DNS::Result.
    }

    my $dns_dcv_result = finish_dns_dcv(
        value => $value,
        state => $state,
        zones => $dns_dcv_zones_ar,
    );

    return [ map { $dns_dcv_result->get_for_domain($_) } @{ $OPTS{'domains'} } ];
}

=head2 $results_ar = finish_dns_dcv( %OPTS )

This completes a DNS DCV operation after DNS changes are published.
Its return is a L<Cpanel::SSL::DCV::DNS::Result> instance.

%OPTS are:

=over

=item * C<value> - The value that the DNS TXT records should have.

=item * C<state> - A L<Cpanel::DnsUtils::Install::Result> instance.

=item * C<zones> - An arrayref of zones that are changed for the DNS DCV.
This should be zones returned from C<get_mutex_and_domain_dcv_zones()>.

=back

=cut

sub finish_dns_dcv (%opts) {

    my ( $value, $state, $zones_ar ) = @opts{qw( value state zones )};

    if ( $state->{'errors'} ) {
        warn $_ for @{ $state->{'errors'} };
    }

    my %altered_zones = ref $state && $state->{'zones_modified'} ? ( map { $_ => 1 } @{ $state->{'zones_modified'} } ) : ();

    my %zone_result;

    my %queries = map {
        (
            Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_NAME() . ".$_",
            [
                Cpanel::SSL::DCV::DNS::Constants::TEST_RECORD_TYPE(),
                $value,
            ]
        );
    } keys %altered_zones;

    # We don’t pass an AnyAncestor object in here because
    # we’ve already reduced the given domains to zone names.
    my $query_results_hr = check_multiple_nonfatal(
        queries => \%queries,
    );

    for my $qname ( keys %$query_results_hr ) {

        # Remove the leaf label because that’s just TEST_RECORD_NAME().
        $zone_result{ $qname =~ s<.+?\.><>r } = $query_results_hr->{$qname};
    }

    return Cpanel::SSL::DCV::DNS::Result->new(
        $value,
        $zones_ar,
        \%zone_result,
    );
}

sub _get_dcv_zones {
    my ( $username, $domains_ar ) = @_;

    my @all_zones = Cpanel::UserZones::User::list_user_dns_zone_names($username);

    my $zone_ancestor_hr = Cpanel::DnsUtils::Name::identify_ancestor_domains( \@all_zones );

    my $dcv_domain_hr = Cpanel::DnsUtils::Name::identify_ancestor_domains($domains_ar);

    my %dcv_zones_lookup;

    my @zones;

    for my $domain (@$domains_ar) {
        my $dcv_domain = $dcv_domain_hr->{$domain} || $domain;

        my $best_zone = Cpanel::DnsUtils::Name::get_longest_short_match( $dcv_domain, \@all_zones ) or do {
            if ($>) {
                die Cpanel::Exception::create( 'EntryDoesNotExist', 'You do not control a domain named “[_1]”.', [$domain] );
            }

            die Cpanel::Exception::create( 'EntryDoesNotExist', '“[_1]” does not control a domain named “[_2]”.', [ $username, $domain ] );
        };

        #In the case of zones where the user controls an ancestor zone,
        #use the ancestor instead.
        $best_zone = $zone_ancestor_hr->{$best_zone} || $best_zone;

        if ( !$dcv_zones_lookup{$best_zone}++ ) {
            push @zones, $best_zone;
        }
    }

    return \@zones;
}

#----------------------------------------------------------------------

#stubbed out in tests
sub _do_recursive_queries {
    my ( $res, $name_qtypes_ar ) = @_;

    return $res->recursive_queries($name_qtypes_ar);
}

our $_DCV_TIMEOUT;

sub _get_dns_dcv_timeout {
    return $_DCV_TIMEOUT if $_DCV_TIMEOUT;
    return ( $_DCV_TIMEOUT = ( Cpanel::Config::LoadCpConf::loadcpconf_not_copy()->{'bind_deferred_restart_time'} + 4.5 ) );

}

sub _dcv_sleep {
    return Cpanel::TimeHiRes::sleep(0.25);
}

1;
