package Cpanel::SSL::CAA;

# cpanel - Cpanel/SSL/CAA.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::CAA

=head1 SYNOPSIS

    use Cpanel::SSL::CAA ();

    my @added = Cpanel::SSL::CAA::ensure_ca_authorization(
        [ 'sectigo.com', 'comodoca.com' ],

        'example.com',
        'www.example.com',
        'cpanel.example.com',

        # … etc.
    );

    # XXX VERY IMPORTANT!!! …
    _wait_for_reload() if @added;

    # Callers are expected to implement these:
    _notify_about_updates(@added);

=head1 DESCRIPTION

This module fetches the domains using
Cpanel::Domain::Zone->new()->get_zones_for_domains
and inserts missing CAA records for the provider.

The zones are then uploaded back to the dnsadmin
system if there are any modifications needed.

=cut

#----------------------------------------------------------------------

use Cpanel::ArrayFunc::Uniq        ();
use Cpanel::Validate::Domain       ();
use Cpanel::Domain::Zone           ();
use Cpanel::Set                    ();
use Cpanel::ZoneFile               ();
use Cpanel::DnsUtils::AskDnsAdmin  ();
use Cpanel::DnsUtils::CAA          ();
use Cpanel::DnsUtils::GenericRdata ();

use constant _TAG_NAMES => qw( issue  issuewild );

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @added = ensure_ca_authorization( \@CAA_STRINGS, @DOMAINS );

B<IMPORTANT:> If this function returns nonempty, you B<must> implement
a suitable wait to allow DNS changes to propagate to all nameservers in
the local cluster.

For each @DOMAINS, attempt to ensure that the provider that the given
@CAA_STRINGS represent can issue an SSL certificate for that domain.

For both the C<issue> and C<issuewild> CAA tags, this ensures that either
no CAA records exist for the given domain or that the existing CAA record set
includes a record for at least one of @CAA_STRINGS. If that isn’t already the
case, such a record is added, using the first member of @CAA_STRINGS.

The end result is that, for both C<issue> and C<issuewild>, any domain that
has a CAA record has at least one for the CA that the @CAA_STRINGS represent.

The return is a list of 2-member array references: [ $domain => $tag ].
Each pair indicates a DNS update that occurred. (In scalar context, the
number of such items that would be returned in list context is returned.)

NB: This function used to remove duplicate entries. This appears to have
been solely to accommodate a bug that surfaced in the original development
cycle. (cf. SWAT-1200) In the interest of simplifying this code, that
deduplication logic is removed as of v86. While PowerDNS does, at least as of
4.1.10, warn about duplicate CAA records, those duplicates would only come
about as a result of user action.

=cut

sub ensure_ca_authorization ( $provider_strs_ar, @domains ) {

    if ( !UNIVERSAL::isa( $provider_strs_ar, 'ARRAY' ) ) {
        die 'First arg must be ARRAY ref.';
    }

    if ( !@domains ) {
        die 'No domains were provided for CAA verification.';
    }

    _remove_invalid_and_collapse_wildcard_domains( \@domains );

    #
    # Its important to use get_zones_for_domains here
    # since @domains could be a subset of domains since autossl
    # could be running on a newly setup vhost and the parent domain
    # already has a valid ssl which would mean it would not be up for renewal
    # and not be in @domains

    local $@;

    my ( $domain_to_zone_map_hr, $zones_hr ) = eval { Cpanel::Domain::Zone->new()->get_zones_for_domains( \@domains ); };

    if ( !$zones_hr ) {
        warn "get_zones_for_domains(): $@";
        return 0;
    }

    my @all_expected_zones = Cpanel::ArrayFunc::Uniq::uniq( values %$domain_to_zone_map_hr );

    my %zone_obj;
    my %caa_records_by_name;

    for my $zone (@all_expected_zones) {
        if ( !$zones_hr->{$zone} ) {

            # This has to match the error in Whostmgr::DNS
            # for the tests to pass.
            #
            # TODO: We may be able to remove this compatiblity
            # requirement in v78+ with some analysis
            warn "$zone: No data read from zone file.";
            next;
        }

        if ( !_zone_text_sr_can_contain_a_caa_record( $zones_hr->{$zone} ) ) {

            # Avoid parsing zones that can never contain
            # a CAA or TYPE257 record
            next;
        }

        $zone_obj{$zone} = Cpanel::ZoneFile->new( 'domain' => $zone, 'text' => $zones_hr->{$zone} );

        # TYPE257 is a way of writing CAA records that works in old BIND versions.
        # Cpanel::ZoneFile parses TYPE257 as just a normal CAA record,
        # so we shouldn’t need to look explicitly for TYPE257,
        # but we still look for both here just in case.
        # Read more about the TYPE257 format in RFC 3597.
        my @records_found = (
            $zone_obj{$zone}->find_records( 'type' => 'CAA' ),
            $zone_obj{$zone}->find_records( 'type' => 'TYPE257' ),
        );

        foreach my $record (@records_found) {
            push @{ $caa_records_by_name{ $record->{name} } }, $record;
        }
    }

    my @added;

    for my $domain (@domains) {
        my $zone = $domain_to_zone_map_hr->{$domain} or do {
            warn "MISSING DNS ZONE: $domain!\n";
            next;
        };

        my $zf = $zone_obj{$zone} or next;

        next if !$caa_records_by_name{"$domain."};

        my @caa_recs = @{ $caa_records_by_name{"$domain."} };

        # Indexed on the CAA record value domain (e.g., “comodoca.com”):
        my %tag_value_domain_lookup = map { $_ => {} } _TAG_NAMES();

        for my $tag ( _TAG_NAMES() ) {
            my $value_domain_lookup_hr = $tag_value_domain_lookup{$tag};

            foreach my $caa_rec (@caa_recs) {
                next if $caa_rec->{'tag'} ne $tag;

                # CAA “issue” and “issuewild” records can contain
                # optional key/value pairs after a semicolon.
                # RFC 8647 defines one such usage; more may materialize.
                #
                my ($value_domain) = $caa_rec->{'value'} =~ m<\A([^;]*)>;

                $tag_value_domain_lookup{$tag}{$value_domain} = 1;
            }
        }

        for my $tag ( _TAG_NAMES() ) {
            my @match = Cpanel::Set::intersection(
                [ keys %{ $tag_value_domain_lookup{$tag} } ],
                $provider_strs_ar,
            );

            if ( !@match ) {
                my @nonmatch = Cpanel::Set::difference(
                    [ keys %{ $tag_value_domain_lookup{$tag} } ],
                    $provider_strs_ar,
                );

                if (@nonmatch) {
                    $zf->add_record( _build_caa_record( $domain, $provider_strs_ar->[0], $tag ) );
                    push @added, [ $domain => $tag ];
                }
            }
        }
    }

    my %synczones_query;

    for my $zone (@all_expected_zones) {
        my $zf = $zone_obj{$zone} or next;

        if ( $zf->get_modified() ) {
            $synczones_query{ 'cpdnszone-' . $zone } = $zf->to_zone_string();
        }
    }

    _send_updated_zones_if_modified( \%synczones_query );

    return @added;
}

sub _remove_invalid_and_collapse_wildcard_domains {
    my ($domains_ar) = @_;
    @$domains_ar = grep {
        Cpanel::Validate::Domain::valid_wild_domainname($_) || do {

            # This has to match the error in Whostmgr::DNS
            # for the tests to pass.
            #
            # TODO: We may be able to remove this compatiblity
            # requirement in v78+ with some analysis
            warn "$_: Invalid domain specified";

            0;
        };
    } @$domains_ar;

    for my $domain (@$domains_ar) {
        next if 0 != rindex( $domain, '*.', 0 );

        substr( $domain, 0, 2, q<> );
    }

    @$domains_ar = Cpanel::ArrayFunc::Uniq::uniq(@$domains_ar);
    return 1;
}

sub _send_updated_zones_if_modified {
    my ($synczones_query_hr) = @_;

    if ( keys %$synczones_query_hr ) {
        my @zones_to_reload;

        local $@;

        my $synced_ok = eval {
            Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin(
                'SYNCZONES',
                $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL, q{}, q{}, q{},
                $synczones_query_hr,
            );

            1;
        };

        if ($synced_ok) {
            push @zones_to_reload, sort map { s/^cpdnszone-//r } keys %$synczones_query_hr;

            my $reload_ok = eval {
                Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin(
                    'RELOADZONES',
                    $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL,
                    join( ',', @zones_to_reload ),
                );

                1;
            };

            warn "RELOADZONES: $@" if !$reload_ok;
        }
        else {
            warn "SYNCZONES: $@";
        }
    }

    return;
}

# This function converts a CAA record to the 'legacy' TYPE257
sub _convert_caa_record_to_legacy_value {
    my ( $tag, $flag, $value ) = @_;

    my $rdata = Cpanel::DnsUtils::CAA::encode_rdata( $flag, $tag, $value );

    return Cpanel::DnsUtils::GenericRdata::encode($rdata);
}

sub _build_caa_record {
    my ( $domain, $provider_str, $tag ) = @_;
    my $record = {
        'name'  => $domain . '.',
        'class' => 'IN',
        'type'  => 'CAA',
        'flag'  => 0,
        'tag'   => $tag,
        'value' => $provider_str,
    };

    $record->{'value_legacy'} = _convert_caa_record_to_legacy_value( $record->{'tag'}, $record->{'flag'}, $record->{'value'} );
    return $record;
}

sub _zone_text_sr_can_contain_a_caa_record {
    my ($zone_text_sr) = @_;

    return $zone_text_sr =~ m{[ \t]+(?:CAA|TYPE257)[ \t]+}is;
}

1;
