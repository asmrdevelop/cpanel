package Cpanel::DNS::GetNameservers;

# cpanel - Cpanel/DNS/GetNameservers.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception;
use Time::HiRes ();

=encoding utf-8

=head1 NAME

Cpanel::DNS::GetNameservers

=head1 SYNOPSIS

    my $name_ip = Cpanel::DNS::GetNameservers::get_nameservers(
        $unbound_obj,
        'some-name.tld',
    );

=head1 DESCRIPTION

DNS logic related to nameserver queries.

=cut

#----------------------------------------------------------------------

my %IGNORE_DNS_ERROR = (
    NOERROR  => 1,
    NXDOMAIN => 1,
    SERVFAIL => 1,
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $nss_hr = get_nameservers( $UNBOUND_OBJ, $DOMAIN_NAME, $CONSIDER_SOA, $GET_IPS )

Fetches $DOMAIN_NAME’s authoritative nameservers, and optionally their IPs.

L<libunbound|https://nlnetlabs.nl/projects/unbound/>, for security reasons,
does not consider AUTHORITY records as valid answers for NS queries. Thus,
if a domain is registered but its authoritative nameservers aren’t active
yet, libunbound won’t tell you what those authoritative nameservers are
because the TLD’s nameservers will indicate the domain’s configured
nameservers in the AUTHORITY section of a DNS query response.

If that’s unclear, do this:

    dig @a.gtld-servers.net cpanel.net NS

The nameservers in the response’s AUTHORITY section are the registered
nameservers. If none of those nameservers were inactive, libunbound would
give an empty response. This function exists to correct that, so that
if libunbound gives empty then we probe that extra level deeper to give
back the AUTHORITY records.

If you wish to consider SOA records to be equivalent to SOA records,
however, you can always pass CONSIDER_SOA=1 to this function, which will
replace all NS queries with SOA queries.  It is up to the caller to merge
NS and SOA data if applicable.

The return value is a hash reference of name to an array reference of
IP addresses, unless GET_IPS is false, in which case the IP values will
be undef.

Note that if $DOMAIN_NAME is a subdomain of a registered domain,
this returns the nameservers for $DOMAIN_NAME’s longest parent domain.

=cut

sub get_nameservers ( $unbound, $domain, $consider_soa = 0, $get_ips = 1 ) {    ## no critic qw(Proto ProhibitManyArgs)

    # 1) Fetch nameservers for $domain and all of its parent domains:

    my @queries;
    my @pieces = split m<\.>, $domain;
    for my $n ( 0 .. $#pieces ) {
        my $name  = join( '.', @pieces[ ( $#pieces - $n ) .. $#pieces ] );
        my $qtype = $consider_soa ? 'SOA' : 'NS';
        unshift @queries, [ $name, $qtype ];
    }

    my $ret = $unbound->recursive_queries( \@queries );

    # 2) Determine the longest domain that turned up an answer:

    my $first_responsive_nameservers;
    my $first_responsive_nss_are_for_tld = 0;

    while ( my $result = shift @$ret ) {
        my $query_domain = ( shift @queries )->[0];

        next if !$result->{'decoded_data'} || !@{ $result->{'decoded_data'} };

        $first_responsive_nameservers = $result->{'decoded_data'};
        if ( $result->{qtype} eq 'SOA' ) {
            $first_responsive_nameservers = [ $result->{decoded_data}->[0]->{mname} ];
        }

        $first_responsive_nss_are_for_tld = $query_domain ne $domain;

        $first_responsive_nss_are_for_tld &&= do {
            require Cpanel::PublicSuffix;
            Cpanel::PublicSuffix::domain_isa_tld($query_domain);
        };

        last;
    }

    my $ns_addr_hr;

    if ($first_responsive_nameservers) {

        # For now just look up A records; we can add AAAA later if that’s
        # useful.  We can't avoid this even if we don't care about the NS IPs, unfortunately.
        my $ip_lookup_hr = {};
        $ip_lookup_hr = $unbound->get_records_by_domains( 'A', @$first_responsive_nameservers );

        my @names;

        if ($first_responsive_nss_are_for_tld) {

            # We can proceed as long as we have at least one IP address.
            # If we have none, though, then we can’t proceed.
            my $total_ip_lookup_failure_yn = !grep { $_ && @$_ } values %$ip_lookup_hr;

            if ($total_ip_lookup_failure_yn) {
                my @ns_names = sort keys %$ip_lookup_hr;

                die Cpanel::Exception->create( 'The system failed to find the [asis,IPv4] [numerate,_1,address,addresses] for [list_and_quoted,_2]. Because of this, the system cannot find “[_3]”’s authoritative nameservers. See the [asis,cPanel amp() WHM] error log for more details.', [ 0 + @ns_names, \@ns_names, $domain ] );
            }

            my @nss = map { $_ ? @$_ : () } values %$ip_lookup_hr;

            # You might think that the recursive_queries above would just get the nameservers. Ha.
            # In the event that the NS are the *only* thing setup, and as part of the parent zone, unbound can't see them.
            # So, we have to interrogate them directly to get the NS, which we can then ask unbound again as to their A records.
            @names = _find_names_and_ips_with_nameservers_for_domain( $domain, \@nss, $ip_lookup_hr, $unbound, $get_ips );
        }
        else {
            @names = @$first_responsive_nameservers;
        }

        $ns_addr_hr = { %$ip_lookup_hr{@names} };

        #Strip IPs which we *might* have if we don't care
        @$ns_addr_hr{@names} = map { undef } @names unless $get_ips;
    }

    return $ns_addr_hr;
}

sub _find_names_and_ips_with_nameservers_for_domain {
    my ( $domain, $nameservers_ar, $ip_lookup_hr, $unbound, $get_ips ) = @_;
    require Net::DNS::Resolver;
    my $dns = Net::DNS::Resolver->new( nameservers => $nameservers_ar, tcp_timeout => 5, udp_timeout => 4 );

    my @names;

    my $handle = $dns->bgsend( $domain, 'NS' );
    while ( $handle && $dns->bgbusy($handle) ) { Time::HiRes::nanosleep(100_000_000); }

    if ( $handle && ( my $pkt = $dns->bgread($handle) ) ) {

        my $rcode = $pkt->header()->rcode();

        if ( !$IGNORE_DNS_ERROR{$rcode} && ( !( $rcode eq 'REFUSED' && $domain =~ m{\.(?:test|invalid)$} ) ) ) {
            warn $pkt->string();
        }

        # Gotta check the record type because we might get an SOA.
        # (Maybe there are other possibilities?)
        @names = map { $_->isa('Net::DNS::RR::NS') ? $_->nsdname() : () } $pkt->answer(), $pkt->authority();

        for my $rr ( $pkt->additional() ) {

            #just in case we didn't find it yet!
            if ( grep { $rr->type eq $_ } qw{A AAAA} ) {
                $ip_lookup_hr->{ $rr->owner() } //= [];
                push @{ $ip_lookup_hr->{ $rr->owner() } }, $rr->address();
            }
        }

        # There is no guarantee that the A records for the NS will be in the additional data returned, so query for that as well
        # Furthermore, there is no guarantee that the gtld knows, given they could be on entirely different gTLDs
        # So, let's ask unbound, since it just asks the roots.
        _get_ns_ips( $unbound, $ip_lookup_hr, @names ) if $get_ips;
    }
    else {
        warn( "DNS query ($domain/NS) error: " . $dns->errorstring() );
    }

    return @names;
}

sub _get_ns_ips {
    my ( $unbound, $ip_lookup_hr, @names ) = @_;
    foreach my $ns (@names) {
        next if $ip_lookup_hr->{$ns};

        my $reply = $unbound->recursive_queries( [ [ $ns, 'A' ], [ $ns, 'AAAA' ] ] );
        while ( my $result = shift @$reply ) {
            if ( $result->{error} ) {
                warn Cpanel::Exception::get_string( $result->{error} );
                next;
            }
            $ip_lookup_hr->{$ns} //= [];
            push( @{ $ip_lookup_hr->{$ns} }, @{ $result->{decoded_data} } ) if ref $result->{decoded_data} eq 'ARRAY';
        }
    }
    return $ip_lookup_hr;
}

1;
