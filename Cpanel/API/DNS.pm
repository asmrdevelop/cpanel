package Cpanel::API::DNS;

# cpanel - Cpanel/API/DNS.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::API::DNS

=head1 DESCRIPTION

This module contains UAPI methods related to DNS.

=head1 SYNOPSIS

  use Cpanel::API::DNS ();

  # lookup a host
  Cpanel::API::DNS::lookup('example.com');

=head1 FUNCTIONS

=cut

use cPstrict;

use Cpanel::Imports;

use Cpanel                            ();
use Cpanel::Args::CpanelUser::Domains ();
use Cpanel::DnsRoots                  ();
use Cpanel::Exception                 ();
use Cpanel::Logger                    ();
use Cpanel::Net                       ();

use Try::Tiny;

our $_DEBUG = Cpanel::Logger::is_sandbox() ? 1 : 0;    #XXX FIXME turn this off when ready to ship

#This accepts a list of “domain”s (domain, domain-1, etc.) and
#returns, for each domain, one of:
#   - undef, if the domain has 1+ domains on the server and 0 elsewhere
#   - Which of those criteria are not met.
#
#So, if I pass in:
#   domain      => 'this-resolves.com',
#   domain-1    => 'does-not-resolve.com',
#
#...I’ll get back something like:
#   [
#       undef,
#       'This is why I don’t like your domain …',
#   ]
#
# NB: This does NOT require the DNS role.
#
sub ensure_domains_reside_only_locally {
    my ( $args, $result ) = @_;

    my $resolver = Cpanel::DnsRoots->new();
    my @resolved_domains;
    my @domains = $args->get_length_required_multiple('domain');

    foreach my $domain (@domains) {
        my $error;
        try {
            $resolver->ensure_domain_resides_only_locally($domain);
        }
        catch {
            $error = Cpanel::Exception::to_locale_string_no_id($_);

            undef $error if $_DEBUG;
        };

        push @resolved_domains, $error;
    }

    return $result->data( \@resolved_domains );
}

sub parse_zone ( $args, $result, @ ) {    # note: this is more a fetch_zone than a parse_zone :-)

    my $zonename = $args->get_length_required('zone');

    require Cpanel::ZoneEdit;
    require Cpanel::ZoneFile::Parse;

    return 0 if !_zone_is_valid_or_set_result_error( $zonename, $result );

    my $zone_text = Cpanel::ZoneEdit::fetchzone_raw($zonename);

    return $result->data( Cpanel::ZoneFile::Parse::parse_string_to_b64( $zone_text, $zonename ) );
}

sub _zone_is_valid_or_set_result_error ( $zonename, $result ) {
    require Cpanel::UserZones::User;
    my @user_zones = Cpanel::UserZones::User::list_user_dns_zone_names($Cpanel::user);

    if ( !grep { $_ eq $zonename } @user_zones ) {
        $result->raw_error( locale()->maketext( 'You do not control a [asis,DNS] zone named “[_1]”.', $zonename ) );
        return 0;
    }

    return 1;
}

=head2 fetch_cpanel_generated_domains

Fetch cpanel generated domains.

B<ARGUMENTS>

=over

=item domain - string [required]

Provide the domain name.

=back

B<EXAMPLES>

* Fetch all domains

        uapi --output=jsonpretty --user=cpuser DNS fetch_cpanel_generated_domains domain=domain.test

The returned data will contain a structure similar to the JSON below:

        {
            "apiversion" : 3,
            "func" : "fetch_cpanel_generated_domains",
            "module" : "DNS",
            "result" : {
                "data" : [
                    {
                        "domain" : "domain.test."
                    },
                    {
                        "domain" : "webmail.domain.test."
                    },
                    ...
                ],
                "errors" : null,
                "messages" : null,
                "metadata" : {
                    "transformed" : 1
                },
                "status" : 1,
                "warnings" : null
            }
        }

=cut

sub fetch_cpanel_generated_domains ( $args, $result ) {

    require Cpanel::ZoneEdit;

    my $domain = $args->get_length_required(qw{ domain });
    my $data   = Cpanel::ZoneEdit::api2_fetch_cpanel_generated_domains( domain => $domain );

    return $result->data($data);
}

=head2 mass_edit_zone

L<https://go.cpanel.net/dns-mass_edit_zone>

=cut

sub mass_edit_zone ( $args, $result, @ ) {
    require Cpanel::APICommon::DNS;

    my @accepted_rr_types = _get_accepted_rr_types_or_die();

    my %accepted_lookup = map { $_ => undef } @accepted_rr_types;

    my $zonename = $args->get_length_required('zone');
    my $serial   = $args->get_length_required('serial');

    my @additions = $args->get_length_multiple('add');
    my @edits     = $args->get_length_multiple('edit');
    my @removals  = $args->get_length_multiple('remove');

    return 0 if !_zone_is_valid_or_set_result_error( $zonename, $result );

    if ( !@additions && !@edits && !@removals ) {
        $result->raw_error( locale()->maketext('You must provide at least one change to the [asis,DNS] zone.') );
        return 0;
    }

    require Cpanel::JSON;
    $_ = Cpanel::JSON::Load($_) for ( @additions, @edits );

    for my $lineidx (@removals) {
        if ( my $err = Cpanel::APICommon::DNS::get_mass_edit_remove_error($lineidx) ) {
            $result->error($err);
            return 0;
        }
    }

    for my $add_item (@additions) {
        if ( my $err = Cpanel::APICommon::DNS::get_mass_edit_add_error($add_item) ) {
            $result->error($err);
            return 0;
        }

        return 0 if !_authorize_record_type(
            $result,
            $add_item->{'record_type'},
            \%accepted_lookup,
        );

        # Convert to the format that the admin call expects:
        $add_item = [
            @{$add_item}{ 'dname', 'ttl', 'record_type' },
            $add_item->{'data'}->@*,
        ];
    }

    for my $edit_item (@edits) {
        if ( my $err = Cpanel::APICommon::DNS::get_mass_edit_edit_error($edit_item) ) {
            $result->error($err);
            return 0;
        }

        return 0 if !_authorize_record_type(
            $result,
            $edit_item->{'record_type'},
            \%accepted_lookup,
        );

        $edit_item = [
            @{$edit_item}{ 'line_index', 'dname', 'ttl', 'record_type' },
            $edit_item->{'data'}->@*,
        ];
    }

    require Cpanel::AdminBin::Call;
    require Cpanel::Try;

    my $new_serial;

    Cpanel::Try::try(
        sub {
            $new_serial = Cpanel::AdminBin::Call::call(
                'Cpanel', 'zone', 'MASS_EDIT',
                zone      => $zonename,
                serial    => $serial,
                additions => \@additions,
                edits     => \@edits,
                removals  => \@removals,
            );
        },
        'Cpanel::Exception::DNS::InvalidZoneFile' => sub ($err) {
            require Cpanel::APICommon::Error;
            $result->data(
                Cpanel::APICommon::Error::convert_to_payload(
                    'InvalidZoneFile',
                    by_line => $err->get_by_line_utf8(),
                ),
            );

            local $@ = $err;
            die;
        },
        'Cpanel::Exception::Stale' => sub ($err) {
            require Cpanel::APICommon::Error;
            $result->data( Cpanel::APICommon::Error::convert_to_payload('Stale') );
            local $@ = $err;
            die;
        },
    );

    $result->data( { new_serial => $new_serial } );

    return 1;
}

sub _authorize_record_type ( $result, $type, $allowed_hr ) {
    if ( !exists $allowed_hr->{$type} ) {
        my @accepted = sort keys %$allowed_hr;
        $result->raw_error( locale()->maketext( 'This interface cannot create “[_1]” records. It can only create [list_and,_2] records.', $type, \@accepted ) );
        return 0;
    }

    return 1;
}

sub _get_accepted_rr_types_or_die () {
    require Cpanel::ZoneEdit::User;

    my @accepted_rr_types = Cpanel::ZoneEdit::User::get_allowed_record_types(
        \&Cpanel::hasfeature,
    );

    if ( !@accepted_rr_types ) {

        # Sanity-check; normally the %API metadata should
        # prevent us from getting here.
        require Carp;
        Carp::confess('No zone-edit features enabled??');
    }

    return @accepted_rr_types;
}

sub has_local_authority {

    my ( $args, $result ) = @_;

    my $domains = Cpanel::Args::CpanelUser::Domains::validate_domains_or_die($args);

    require Cpanel::AdminBin::Call;
    my $get_soa_and_zones_for_domains = Cpanel::AdminBin::Call::call( 'Cpanel', 'zone', 'GET_SOA_AND_ZONES_FOR_DOMAINS', $domains );

    require Cpanel::DnsUtils::Authority;
    my $has_authority = Cpanel::DnsUtils::Authority::zone_soa_matches_dns_for_domains($get_soa_and_zones_for_domains);

    my %domain_to_zone = map { $_->{domain} => $_->{zone} } @$get_soa_and_zones_for_domains;

    my $results = [];

    foreach my $domain (@$domains) {
        push @$results, {
            domain          => $domain,
            zone            => $domain_to_zone{$domain},
            local_authority => $has_authority->{$domain}{local_authority} || 0,
            nameservers     => $has_authority->{$domain}{nameservers},
            error           => $has_authority->{$domain}{error},
        };
    }

    $result->data($results);

    return 1;
}

sub _is_valid_ip ($ip) {
    require Cpanel::Validate::IP::v4;
    if ( Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
        return 1;
    }
    return 0;
}

sub _invalid_ip ($ip) {
    return locale()->maketext( '“[_1]” is not a valid [asis,IPv4] address.', $ip );
}

sub swap_ip_in_zones ( $args, $result ) {

    my $domains_ar = Cpanel::Args::CpanelUser::Domains::validate_domains_or_die($args);

    # The destination IP is the only one we really need … if source IP is not provided we
    # can auto-detect and if the FTP IP is not provided we can default to the destination
    # IP.
    my $dest_ip = $args->get_length_required('dest_ip');
    my $ftp_ip  = $args->get('ftp_ip') // $dest_ip;

    die _invalid_ip($dest_ip) unless _is_valid_ip($dest_ip);
    die _invalid_ip($ftp_ip)  unless _is_valid_ip($ftp_ip);

    my $source_ip = $args->get('source_ip') // -1;
    if ( $source_ip ne '-1' ) {
        die _invalid_ip($source_ip) unless _is_valid_ip($source_ip);
    }

    $result->data( Cpanel::AdminBin::Call::call( 'Cpanel', 'zone', 'SWAP_IP_IN_ZONES', $source_ip, $dest_ip, $ftp_ip, $domains_ar ) );

    return 1;
}

=head2 lookup()

This function returns DNS zone information about a domain.

=head3 ARGUMENTS

=over

=item domain - string

The FQDN of the host to query.

=back

=head3 RETURNS

On success, the method returns an arrayref containing the query results with one item per line.

=head3 THROWS

=over

=item When the domain parameter is not provided

=item When the C<nettools> feature is not enabled.

=item When the account is in demo mode.

=item When the hostname is invalid.

=item Other errors from additional modules used may be possible.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty DNS lookup domain=example.com

The returned data will contain a structure similar to the JSON below:

     "data" : [
         "example.com has address 93.184.216.34",
         "example.com has IPv6 address 2606:2800:220:1:248:1893:25c8:1946",
         "example.com mail is handled by 0 ."
     ]

=head4 Template Toolkit

    [%
    SET result = execute('DNS', 'lookup', {
        domain => 'example.com'
    });
    IF result.status;
        FOREACH item IN result.data %]
            [% item.html() %]<br>
        [% END %]
    [% END %]

=cut

sub lookup {

    my ( $args, $result ) = @_;

    my $domain = $args->get_length_required('domain');
    $result->data( Cpanel::Net::host_lookup($domain) );

    return 1;

}

my $allow_demo = { allow_demo => 1 };

our %API = (
    ensure_domains_reside_only_locally => $allow_demo,
    has_local_authority                => $allow_demo,
    lookup                             => { allow_demo => 0, needs_feature => 'nettools' },
    parse_zone                         => undef,
    mass_edit_zone                     => {
        allow_demo    => 0,
        needs_feature => { match => 'any', features => [qw(simplezoneedit zoneedit changemx)] },
    },
);

1;
