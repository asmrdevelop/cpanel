package Cpanel::Market::Provider::cPStore::Utils;

# cpanel - Cpanel/Market/Provider/cPStore/Utils.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Market::Provider::cPStore::Utils

=head2 DESCRIPTION

This module collects various bits of logic that are specific to the
cPStore provider module but that are useful to test individually.

Ideally, nothing but the cPStore provider module should call into this module.

=cut

use Cpanel::Config::Sources ();
use Cpanel::DIp::MainIP     ();
use Cpanel::HTTP::Client    ();
use Cpanel::JSON            ();
use Cpanel::NAT             ();
use Crypt::Format           ();
use Digest::MD5             ();
use Digest::SHA             ();
use URI                     ();

use Cpanel::Context                              ();
use Cpanel::Config::userdata::Load               ();
use Cpanel::Config::userdata::Utils              ();
use Cpanel::Exception                            ();
use Cpanel::Locale                               ();
use Cpanel::Market::Provider::cPStore::Constants ();
use Cpanel::PwCache                              ();
use Cpanel::SSL::Providers::Sectigo              ();

use Try::Tiny;

use File::Spec ();

=head1 FUNCTIONS

=head2 (FILENAME, CONTENTS) = get_domain_verification_filename_and_contents(CSR_PEM)

Returns the filename and expected contents for HTTP DCV for the given CSR.

This just calls into L<Cpanel::SSL::Providers::Sectigo>; new code should call that module
directly instead.

=cut

sub get_domain_verification_filename_and_contents {
    my ($csr) = @_;

    Cpanel::Context::must_be_list();

    my $strings_hr = Cpanel::SSL::Providers::Sectigo::get_dcv_strings_for_csr($csr);

    return @{$strings_hr}{ 'http_filename', 'http_contents' };
}

=head2 imitate_http_dcv_check_locally( $DOMAIN, $PATH, $CONTENT )

A sanity check to be sure that this server serves up the correct data
for the HTTP DCV check. This does NOT use local DNS;
instead, it does a recursive DNS query to ensure that local DNS’s state
doesn’t affect the outcome.

This is intended to detect things like:

=over

=item * Apache is down

=item * the user blocked *.txt requests

=back

=cut

sub imitate_http_dcv_check_locally {
    my ( $domain, $docroot_relative_path_to_filename, $content, $dns_lookups_hr ) = @_;

    #The filename should not need to be URI-encoded because it’s
    #always of the form: /\A [0-9A-F]{32} \.txt \z/x
    my $url = "http://$domain/$docroot_relative_path_to_filename";

    require Cpanel::SSL::DCV;

    my $check_hr = Cpanel::SSL::DCV::verify_http_with_dns_lookups(
        $url,
        $content,
        Cpanel::Market::Provider::cPStore::Constants::DCV_USER_AGENT(),
        Cpanel::Market::Provider::cPStore::Constants::HTTP_DCV_MAX_REDIRECTS(),
        $dns_lookups_hr,
    );

    if ( $check_hr->{'redirects_count'} ) {
        die Cpanel::Exception->new( 'The [output,abbr,DCV,Domain Control Validation] check for the domain “[_1]” used an [asis,HTTP] redirect from the [asis,URL] “[output,url,_2]”. The [asis,cPanel Store] does not support [asis,HTTP] redirects in [output,abbr,DCV,Domain Control Validation] checks. Remove this redirect, and then try again.', [ $domain, $url ] );
    }

    return;
}

our $_locale;

=head2 $STRING = format_dollars( $NUMBER )

Returns the $NUMBER formatted as for U.S. dollars (USD). The returned
string will be a localized number with two decimal places.

=cut

sub format_dollars {
    my ($num) = @_;

    #We can run into integer size issues here if we
    #handle these as numbers, so convert to string.
    $num .= q<>;

    $num =~ s<(\.[0-9]*[1-9])0+\z><$1>;

    if ( $num =~ m<\.([0-9]+)\z> ) {
        my $decimal_places = length $1;
        die "Invalid dollar amount (>2 decimal places): “$num”\n" if $decimal_places > 2;

        $num .= '1';
        if ( $decimal_places == 1 ) {
            substr( $num, -1, 0, '0' );
        }
    }
    else {
        $num .= '.001';
    }

    $_locale ||= Cpanel::Locale->get_handle();

    my $local_num = $_locale->numf($num);

    return substr( $local_num, 0, length($local_num) - 1 );
}

=head2 ( $NAMES_AR, $VALUE ) = get_dns_dcv_preparation_for_csr( %OPTS )

This returns the minimal set of DNS record names necessary to validate all
of the given domains along with the CNAME entry to create for each of those
domains.

%OPTS is:

=over

=item * C<csr> - The CSR, in PEM format.

=item * C<domains> - An array reference of strings. Must not include any
domains that are not on the CSR.

=back

$NAMES_AR will likely be smaller than C<domains> because of “ancestor DCV”
(e.g., DCV of “example.com” implies validation of all of that domain’s
subdomains).

=cut

sub get_dns_dcv_preparation_for_csr {
    my (%opts) = @_;

    my $csr        = $opts{'csr'}     || die "Need “csr”!";
    my $domains_ar = $opts{'domains'} || die "Need “domains”!";

    my ( $name, $value ) = do {
        my $strings_hr = Cpanel::SSL::Providers::Sectigo::get_dcv_strings_for_csr($csr);
        @{$strings_hr}{ 'dns_name', 'dns_value' };
    };

    require Cpanel::DnsUtils::Name;
    require Cpanel::ArrayFunc::Uniq;

    # Sectigo does DCV for a wildcard domain by doing DCV on the
    # non-wildcard component of the domain.
    my @wc_stripped_domains = map { s<\A\*\.><>r } @$domains_ar;

    my $ancestor_hr = Cpanel::DnsUtils::Name::identify_ancestor_domains( \@wc_stripped_domains );

    my @minimum_domains = Cpanel::ArrayFunc::Uniq::uniq(
        values(%$ancestor_hr),
        grep { !$ancestor_hr->{$_} } @wc_stripped_domains,
    );

    substr( $_, 0, 0, "$name." ) for @minimum_domains;

    return ( \@minimum_domains, $value );
}

sub _get_domain_file {
    return File::Spec->catfile( Cpanel::PwCache::gethomedir(), '.cpanel/store_purchase_domain.json' );
}

sub _ipaddrs {
    my $mainip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );

    my $http     = Cpanel::HTTP::Client->new( timeout => 15 )->die_on_http_error();
    my $url      = Cpanel::Config::Sources::get_source('VERIFY_URL') . q{/ipaddrs.cgi?ip=} . $mainip;
    my $response = $http->get($url);
    if ( !$response->success ) {
        die Cpanel::Exception::create(
            'HTTP::Server',
            [
                method  => 'GET',
                url     => $url,
                status  => $response->status,
                content => $response->content,
                reason  => $response->reason
            ]
        );
    }

    return Cpanel::JSON::Load( $response->{content} );
}

sub is_licensed {
    my %query = @_;

    defined( $query{product_id} ) or defined( $query{package_id_re} ) or do {
        require Carp;
        Carp::confess('You must specify product_id and/or package_id_re.');
    };

    my $data = _ipaddrs();

    foreach my $license ( @{ $data->{current} } ) {
        next if $license->{status} ne 1 or $license->{valid} ne 1;

        return 1 if ( ( !$query{product_id} || $license->{product} eq $query{product_id} )
            && ( !$query{package_id_re} || $license->{package} =~ $query{package_id_re} ) );
    }

    return 0;
}

=head2 is_licensed_by_domain( product_id => $product_id )

Takes a cPanel store product as an argument.
Checks all the domains from that account.
Returns a hash of domains with 1 or 0
if they are licensed or not.

=head3 ARGUMENTS

=over

=item Hash - key: product_id - value: string of the product id from the cPanel Store.

=back

=head3 RETURNS

Hash of domains

    {
        "example1.com" => 0,
        "example2.com" => 1,
    }

=cut

sub is_licensed_by_domain {
    my %arg = @_;

    defined( $arg{product_id} ) or do {
        require Carp;
        Carp::confess('You must specify product_id');
    };

    my $product = lc $arg{product_id};

    my $http            = Cpanel::HTTP::Client->new( timeout => 15 )->die_on_http_error();
    my $ud_main         = Cpanel::Config::userdata::Load::load_userdata_main($Cpanel::user);
    my @account_domains = Cpanel::Config::userdata::Utils::get_all_domains_from_main_userdata($ud_main);
    my $verify_url      = Cpanel::Config::Sources::get_source('VERIFY_URL') . "/api/product/$product/check";

    my $req_json = Cpanel::JSON::Dump( { 'domains' => \@account_domains } );
    my $resp_obj = eval { $http->post( $verify_url, { 'content' => $req_json } ) };

    if ($@) {
        my $locale = Cpanel::Locale->get_handle();
        die $locale->maketext( "The system could not connect to the [asis,cPanel Store] server: [_1]", URI->new($verify_url)->authority );
    }
    elsif ( !$resp_obj->success() ) {
        die Cpanel::Exception::create(
            'HTTP::Server',
            [
                method  => 'POST',
                url     => $verify_url,
                status  => $resp_obj->status,
                content => $resp_obj->content,
                reason  => $resp_obj->reason
            ]
        );
    }

    my $resp_content      = Cpanel::JSON::Load( $resp_obj->content );
    my $available_domains = $resp_content->{domains};
    my %domains_with_license;

    my $session_data = get_session_data()->{license};

    foreach my $i ( 0 .. $#{$available_domains} ) {
        my $value  = ${$available_domains}[$i];
        my $domain = $account_domains[$i];

        next if ( $value eq "invalid" );

        my $isLicensed = undef;

        if ( $value eq "unavailable" || $session_data->{$domain} ) {
            $isLicensed = 1;
        }
        elsif ( $value eq "available" ) {
            $isLicensed = 0;
        }

        $domains_with_license{$domain} = $isLicensed;
    }

    return \%domains_with_license;
}

sub get_license_details {
    my ($domain) = @_;

    if ( !defined($domain) ) {
        require Carp;
        Carp::confess('You must specify a domain.');
    }

    my $session_data = get_session_data()->{current};

    my $token        = $session_data->{token};
    my $product_name = $session_data->{product_name};

    my $url  = Cpanel::Config::Sources::get_source('VERIFY_URL') . "/api/product/$product_name/$domain";
    my $http = Cpanel::HTTP::Client->new( timeout => 15 )->die_on_http_error();
    $http->set_default_header( 'Authorization', "Bearer $token" );

    my $response = $http->get($url);

    if ( !$response->success ) {
        die Cpanel::Exception::create(
            'HTTP::Server',
            [
                method  => 'GET',
                url     => $url,
                status  => $response->status,
                content => $response->content,
                reason  => $response->reason
            ]
        );
    }

    return Cpanel::JSON::Load( $response->{content} )->{data}{aux_key};
}

=head2 save_session_data(DATA)

Given a data structure, DATA, stores it in ~/.cpanel/store_purchase_domain.json
for later use during the purchase process.

See also: Cpanel::API::Market

=cut

sub save_session_data {
    my ($data) = @_;
    $data->{current} //= {};
    $data->{license} //= {};
    Cpanel::JSON::DumpFile( _get_domain_file(), $data );
    return;
}

=head2 get_session_data()

Loads session data from ~/.cpanel/store_purchase_domain.json for use in continuing
a purchase process that has already been started.

See also: Cpanel::API::Market

=cut

sub get_session_data {
    unless ( -e _get_domain_file() ) {
        return {
            current => {},
            license => {},
        };
    }
    return Cpanel::JSON::LoadFile( _get_domain_file() );
}

1;
