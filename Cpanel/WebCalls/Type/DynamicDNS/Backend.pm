package Cpanel::WebCalls::Type::DynamicDNS::Backend;

# cpanel - Cpanel/WebCalls/Type/DynamicDNS/Backend.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::WebCalls::Type::DynamicDNS::Backend

=head1 DESCRIPTION

This module contains implementation logic for
L<Cpanel::WebCalls::Type::DynamicDNS>. Don’t use it from any other
module; if you need something from here, please refactor it to a
different namespace.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::WebVhosts      ();
use Cpanel::DnsUtils::Name ();

# exposed for testing
our $MAX_DESCRIPTION_LENGTH = 1024;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $obj = why_user_and_domain_invalid( $USERNAME, $DOMAIN )

This function implements specific user/domain validation; i.e.,
can this user own that domain.

It is assumed that $USERNAME and $DOMAIN are both well-formed.

=cut

sub why_user_and_domain_invalid ( $username, $domain ) {
    my @domains = Cpanel::WebVhosts::list_ssl_capable_domains($username);
    $_ = $_->{'domain'} for @domains;

    if ( grep { $_ eq $domain } @domains ) {
        return locale()->maketext( "The domain “[_1]” already exists.", $domain );
    }

    my $has_parent = grep { Cpanel::DnsUtils::Name::is_subdomain_of( $domain, $_ ); } @domains;

    if ( !$has_parent ) {
        return locale()->maketext( "The “[_1]” parameter must be a subdomain of an existing domain.", "domain" );
    }

    return undef;
}

=head2 $obj = why_description_invalid( $DESCRIPTION )

Give a reason why $DESCRIPTION is invalid.

=cut

sub why_description_invalid ($description) {
    if ( length $description ) {
        if ( $description =~ tr<\x00-\x1f\x7f><> ) {
            return locale()->maketext( "The “[_1]” parameter cannot contain control characters.", "description" );
        }

        my $copy = $description;
        if ( length($copy) > $MAX_DESCRIPTION_LENGTH ) {
            my $len = length $copy;

            return locale()->maketext( "The “[_1]” parameter ([quant,_2,byte,bytes]) is too long. The maximum allowed length is [quant,_3,byte,bytes].", "description", $len, $MAX_DESCRIPTION_LENGTH );
        }

        if ( !utf8::decode($copy) ) {
            return locale()->maketext( "The “[_1]” parameter must be in valid [asis,UTF-8] format.", "description" );
        }
    }

    return undef;
}

=head2 $obj = why_domain_alone_invalid( $DOMAIN )

Give a reason why $DOMAIN is (intrinsically) invalid.

=cut

sub why_domain_alone_invalid ($domain) {
    if ( !length $domain ) {
        return locale()->maketext( "You must specify the “[_1]” parameter.", "domain" );
    }

    require Cpanel::Validate::Domain;
    my $ok = eval {
        Cpanel::Validate::Domain::valid_rfc_domainname_or_die($domain);
        1;
    };

    if ( !$ok ) {
        return $@->to_locale_string_no_id();
    }

    require Cpanel::WebVhosts::AutoDomains;
    for my $label ( Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_AUTO_DOMAINS() ) {
        if ( 0 == rindex( $domain, "$label.", 0 ) ) {
            return locale()->maketext( "“[_1]” is a reserved subdomain.", $label );
        }
    }

    return undef;
}

=head2 $yn = is_dupe_domain( $USERNAME, $DOMAIN )

Indicates if $USERNAME already has a dynamic DNS entry for $DOMAIN.

=cut

sub is_dupe_domain ( $username, $domain ) {
    my @entries;

    if ($>) {
        require Cpanel::AdminBin::Call;
        require Cpanel::WebCalls::Entry::DynamicDNS;

        my $existing_hr = Cpanel::AdminBin::Call::call(
            'Cpanel', 'webcalls', 'GET_ENTRIES',
        );

        @entries = grep { $_->{'type'} eq 'DynamicDNS' } values %$existing_hr;

        Cpanel::WebCalls::Entry::DynamicDNS->adopt($_) for @entries;
    }
    else {
        require Cpanel::WebCalls::Datastore::Read;
        my $existing_hr = Cpanel::WebCalls::Datastore::Read->read_for_user($username);

        @entries = grep { $_->isa('Cpanel::WebCalls::Entry::DynamicDNS'); } values %$existing_hr;
    }

    if ( grep { $_->domain() eq $domain } @entries ) {
        return 1;
    }

    return 0;
}

=head2 $obj = needs_update( $ID, $ENTRY_OBJ, \%INPUT )

Returns a boolean that indicates whether the related webcall needs to update
DNS.

=cut

sub needs_update ( $id, $entry_obj, $input_hr ) {
    require Cpanel::WebCalls::Datastore::Read;
    my $username = Cpanel::WebCalls::Datastore::Read->get_username_for_id($id);

    my $domain = $entry_obj->domain();

    my @search_types = (
        ( $input_hr->{'ipv4'} ? 'A'    : () ),
        ( $input_hr->{'ipv6'} ? 'AAAA' : () ),
    );

    require Cpanel::DnsUtils::LocalQuery;
    my $asker = Cpanel::DnsUtils::LocalQuery->new( username => $username );
    my ($rrs_ar) = $asker->ask_batch_sync( [ $domain, @search_types ] );

    my %got_result;

    for my $rr (@$rrs_ar) {
        if ( $rr->isa('Net::DNS::RR::A') ) {
            $got_result{'ipv4'} = undef;
            return 1 if $rr->address() ne $input_hr->{'ipv4'};
        }
        elsif ( $rr->isa('Net::DNS::RR::AAAA') ) {
            $got_result{'ipv6'} = undef;
            my $dns = _normalize_ipv6( $rr->address() );

            my $input = _normalize_ipv6( $input_hr->{'ipv6'} );

            return 1 if $dns ne $input;
        }
    }

    my @missing = grep { !exists $got_result{$_} } keys %$input_hr;

    return 0 + @missing;
}

sub _normalize_ipv6 ($address) {

    # This doesn’t need RFC 5952 normalization because we’re
    # normalizing solely for the sake of comparison.
    require Cpanel::IPv6::Normalize;

    my ( $ok, $norm ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($address);
    die $norm if !$ok;

    return $norm;
}

1;
