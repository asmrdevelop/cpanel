package Cpanel::Domain::Zone;

# cpanel - Cpanel/Domain/Zone.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::WebVhosts::AutoDomains       ();
use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Context                      ();

my %_autodomains = map { $_ => 1 } Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_AUTO_DOMAINS();

=encoding utf-8

=head1 NAME

Cpanel::Domain::Zone - Find the zone a domain is in.

=head1 SYNOPSIS

    use Cpanel::Domain::Zone ();

    my $domain_zone_obj = Cpanel::Domain::Zone->new();

    my @possible_domains = $domain_zone_obj->get_possible_zones_for_domain('happy.org');
    my @possible_domains = $domain_zone_obj->get_possible_zones_for_domain('sub.happy.org');

    my $zone = $domain_zone_obj->get_zone_for_domain('sub.happy.org');

=head1 DESCRIPTION

This module figures out which zone a domain is in.  It
compares the list of domains on the system to the zones
that are in dnsadmin.

=cut

sub new {
    my ($class) = @_;

    return bless {}, $class;
}

=head2 get_possible_zones_for_domain($domain)

Returns a list of zones that the domain could be in

The first element in the array is the zone the entry should be in
any additional zones are possible "incorrect" locations for the entry
that need to be checked

There is no way to tell which zone file the record we care about is in
without fetching each zone in the chain and parsing it

Example:
  in zone koston.org        we have  "webdisk.happy IN A x.x.x.x"
  in zone happy.koston.org  we have  "cpanel IN A x.x.x.x"

This function will only tell you where the possible entries are without
checking dnsadmin.  If you are not going to call fetch_zones on all
the possible zones in a later operation to find the entries, use
get_zone_for_domain to find the actual zone.

=cut

# Use this to selectively omit the ownership checks in
# get_possible_zones_for_domain();
our $_forgo_ownership_check_in_get_possible_zones_for_domain;

sub get_possible_zones_for_domain {
    my ( $self, $domain ) = @_;

    Cpanel::Context::must_be_list();

    # Case CPANEL-15787: we need to find the *longest* domain that matches here, not the first one

    # Sadly we have to check getdomainowner because checking userdomains is not
    # race safe since it can get multiple updates within a second.  If you add two
    # subdomains in the same seconds the results will be wrong.

    my @possible_zones;
    my @DNSPATH     = split( /\./, $domain );
    my $first_label = $DNSPATH[0];

    if ( !$_autodomains{$first_label} && ( $_forgo_ownership_check_in_get_possible_zones_for_domain || Cpanel::AcctUtils::DomainOwner::Tiny::domain_has_owner($domain) ) ) {
        push @possible_zones, $domain;
    }

    while ( defined shift @DNSPATH ) {
        last if scalar @DNSPATH == 1;    # no tlds
        my $dns_path_point = join( '.', @DNSPATH );
        push @possible_zones, $dns_path_point if $_forgo_ownership_check_in_get_possible_zones_for_domain || Cpanel::AcctUtils::DomainOwner::Tiny::domain_has_owner($dns_path_point);
    }

    return @possible_zones ? @possible_zones : $domain;
}

=head2 get_zone_for_domain($domain)

This function returns the zone that the domain is located in.

get_zone_for_domain will actually check to see if the zones exist
and figure out the correct zone for the domain.

In order to do so it must actually fetch the zones from the dnsadmin
server which can be expensive

If you have to fetch the zones anyways you iterate the list returned
from get_possible_zones_for_domain and use the first zone
that actually exists returned from that function.

=cut

sub get_zone_for_domain {
    my ( $self, $domain ) = @_;

    my @possible_zones = do {
        local $_forgo_ownership_check_in_get_possible_zones_for_domain = 1;
        $self->get_possible_zones_for_domain($domain);
    };

    return $possible_zones[0] if @possible_zones == 1;

    # The only way we know if a zone exists for the domain is to fetch it.  We could
    # call ZONEEXISTS, but it’s much slower to make a lot of ZONEEXISTS calls
    # than it is to make a single GETZONES call.
    #
    # If dnsadmin ever supports ZONESEXIST we should switch this out.
    require Cpanel::DnsUtils::Fetch;
    require Whostmgr::Transfers::State;
    my $_dns_local          = Whostmgr::Transfers::State::is_transfer() ? $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY : $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL;
    my $zone_ref            = Cpanel::DnsUtils::Fetch::fetch_zones( 'zones' => \@possible_zones, 'flags' => $_dns_local );
    my @zones_with_contents = grep { $zone_ref->{$_} && length $zone_ref->{$_} } @possible_zones;
    return $zones_with_contents[0];
}

=head2 get_zones_for_domains($domains_ar, $pre_fetched_zones_hr)

Inputs:

$domains_ar: A arrayref of domains to find the zones for

$pre_fetched_zones_hr: A hashref of zones to zone contents in the
 format:
    {
       'happy.org' => [ 'zone...', 'file...', 'contents..' ],
       ...,
    }

Returns a hashref mapping domains to the zone they are in
and a hashref of zones.

Example return:

(
    {
       'happy.org' => 'happy.org',
       'sub.happy.org' => 'happy.org',
       ...
    },
    {
       'happy.org' => [ 'zone...', 'file...', 'contents..' ],
       ...,
    }
)

=cut

sub get_zones_for_domains {
    my ( $self, $domains_ar, $pre_fetched_zones_hr ) = @_;

    Cpanel::Context::must_be_list();

    $pre_fetched_zones_hr ||= {};

    my ( $empty_zones_ar, $zones_hr, $possible_domain_to_zone_map_hr ) = $self->_prep_get_zones_for_domains( $domains_ar, $pre_fetched_zones_hr );

    if (@$empty_zones_ar) {
        require Cpanel::DnsUtils::Fetch;
        require Whostmgr::Transfers::State;
        my $_dns_local    = Whostmgr::Transfers::State::is_transfer() ? $Cpanel::DnsUtils::AskDnsAdmin::LOCAL_ONLY : $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL;
        my $fetched_zones = Cpanel::DnsUtils::Fetch::fetch_zones(
            'zones' => $empty_zones_ar,
            'flags' => $_dns_local,
        );

        @{$zones_hr}{ keys %$fetched_zones } = values %$fetched_zones;
    }

    my $domain_to_zone_map_hr = $self->_post_fetch_get_zones_for_domains( $zones_hr, $possible_domain_to_zone_map_hr );

    return ( $domain_to_zone_map_hr, $zones_hr );
}

=head2 promise($ar) = I<OBJ>->async_get_zones_for_domains( $ASYNC_OBJ, \@DOMAINS )

Similar to C<get_zones_for_domains()> but uses non-blocking I/O.
$ASYNC_OBJ is a L<Cpanel::Async::AskDnsAdmin> instance, and @DOMAINS
are to domains to look up.

The returned promise resolves to an arrayref of the same returns as
returned from C<get_zones_for_domains()>.

=cut

sub async_get_zones_for_domains ( $self, $async_obj, $domains_ar ) {
    my ( $empty_zones_ar, $zones_hr, $possible_domain_to_zone_map_hr ) = $self->_prep_get_zones_for_domains($domains_ar);

    my @args = ( zone => join( ',', @$empty_zones_ar ) );

    local ( $@, $! );
    require Whostmgr::Transfers::State;
    my $method = Whostmgr::Transfers::State::is_transfer() ? 'ask_local_only' : 'ask';

    return $async_obj->$method( 'GETZONES', @args )->then(
        sub ($zone_text_hr) {
            @{$zones_hr}{ keys %$zone_text_hr } = values %$zone_text_hr;

            my $domain_to_zone_map_hr = $self->_post_fetch_get_zones_for_domains( $zones_hr, $possible_domain_to_zone_map_hr );

            return [ $domain_to_zone_map_hr, $zones_hr ];
        },
    );
}

#----------------------------------------------------------------------

sub _prep_get_zones_for_domains ( $self, $domains_ar, $pre_fetched_zones_hr = {} ) {    ## no critic qw(ManyArgs) - mis-parse

    my %possible_domain_to_zone_map = do {
        local $_forgo_ownership_check_in_get_possible_zones_for_domain = 1;
        map { $_ => [ $self->get_possible_zones_for_domain($_) ] } @$domains_ar;
    };

    my %all_possible_zones;
    @all_possible_zones{ map { @$_ } values %possible_domain_to_zone_map } = ();

    my %ZONES;

    # The only way we know if a zone exists for the domain is to fetch it.
    @ZONES{ keys %all_possible_zones }    = (undef) x scalar keys %all_possible_zones;
    @ZONES{ keys %$pre_fetched_zones_hr } = @{$pre_fetched_zones_hr}{ keys %$pre_fetched_zones_hr };

    my @empty_zones = grep { !$ZONES{$_} } keys %ZONES;

    return ( \@empty_zones, \%ZONES, \%possible_domain_to_zone_map );
}

sub _post_fetch_get_zones_for_domains ( $, $zones_hr, $possible_domain_to_zone_map_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    my %domain_to_zone_map;

    # Delete empty zones (these don't exist)
    delete @{$zones_hr}{ grep { !$zones_hr->{$_} } keys %$zones_hr };

    foreach my $domain ( keys %$possible_domain_to_zone_map_hr ) {
        foreach my $zone ( @{ $possible_domain_to_zone_map_hr->{$domain} } ) {
            if ( $zones_hr->{$zone} ) {
                $domain_to_zone_map{$domain} = $zone;
                last;
            }
        }
    }

    return \%domain_to_zone_map;
}

1;
