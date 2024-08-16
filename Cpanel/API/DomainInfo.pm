
# cpanel - Cpanel/API/DomainInfo.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module conceives of “domains” as tightly coupled to the concept of
# web virtual hosts rather than as mere DNS entities.
#----------------------------------------------------------------------

package Cpanel::API::DomainInfo;

use strict;
use warnings;

use Cpanel                         ();
use Cpanel::Config::userdata::Load ();
use Cpanel::Locale                 ();
use Cpanel::WebVhosts::Aliases     ();
use Cpanel::HttpUtils::Htaccess    ();

my $locale;

sub _get_domains {

    #
    # Warning: We are modifing data without making a copy
    # here.  This relys on the legacy behavior of fetch_ref
    # in Cpanel::CachedDataStore which is the underlying
    # code for Cpanel::Config::userdata::Load::load_*
    #
    return Cpanel::Config::userdata::Load::load_userdata_main($Cpanel::user);
}

sub main_domain_builtin_subdomain_aliases {
    my ( $args, $result ) = @_;

    $result->data(
        [
            Cpanel::WebVhosts::Aliases::get_builtin_alias_subdomains( ( $Cpanel::CPDATA{'DOMAIN'} ) x 2 ),
        ]
    );

    return 1;
}

# Return a hash datastructure of the domains
#
# parameters:
#   format - 'hash' or 'list' Sets the format of the response (hash is default)
#
# returns {
#    'addon_domains'  => [ { hashref from userdata } ]
#    'sub_domains'    => [ { hashref from userdata } ]
#    'main_domain'    => { hashref from userdata }
#    'parked_domains' => [ dom1, dom2, ... domN ]
# }
#
sub domains_data {
    my ( $args, $result ) = @_;

    my ($format) = $args->get('format') || 'hash';

    my $data = _get_all_domains_data( $args->get('return_https_redirect_status') );

    if ( $format eq 'list' ) {
        my @res;
        push @res, $data->{'main_domain'};
        push @res, @{ $data->{'addon_domains'} };
        push @res, @{ $data->{'sub_domains'} };
        $result->data( \@res );
    }
    else {
        $result->data($data);
    }

    return 1;
}

sub _get_all_domains_data {
    my $get_ssl_redirect_info = shift;
    my $domains_hr            = _get_domains();
    my %res                   = ();

    #
    # Warning: We are modifing data without making a copy
    # here.  This relys on the legacy behavior of fetch_ref
    # in Cpanel::CachedDataStore which is the underlying
    # code for Cpanel::Config::userdata::Load::load_*
    #
    $res{'main_domain'} = _get_domains_info_hr( $domains_hr->{'main_domain'}, 'main_domain' );

    # get listing of sub domains
    my $sub_domains_hr = { map { $_ => _get_domains_info_hr( $_, 'sub_domain' ), } @{ $domains_hr->{'sub_domains'} } };

    my @redirects = Cpanel::HttpUtils::Htaccess::getredirects();

    # get listing of addon domains & generate res
    $res{'addon_domains'} = [
        map {
            # because multiple addon domains might use this, we have to do a top level clone
            my $ad_hr = { %{ $sub_domains_hr->{ $domains_hr->{'addon_domains'}->{$_} } || {} } };
            $ad_hr->{'domain'} = $_;
            $ad_hr->{'type'}   = 'addon_domain';

            for my $redirect (@redirects) {
                if ( $redirect->{'domain'} eq $ad_hr->{'domain'} ) {
                    $ad_hr->{'status'} = $redirect->{'targeturl'};
                    last;
                }
            }
            $ad_hr;
          }
          keys %{ $domains_hr->{'addon_domains'} }
    ];

    # we have to delete afterwards because this was assuming only one parked domain per subdomain
    delete $sub_domains_hr->{ $domains_hr->{'addon_domains'}->{$_} } for keys %{ $domains_hr->{'addon_domains'} };

    # pull just the values from the sub domains and put them into the res
    $res{'sub_domains'}    = [ values %{$sub_domains_hr} ];
    $res{'parked_domains'} = $domains_hr->{'parked_domains'};

    if ($get_ssl_redirect_info) {
        require Cpanel::HttpUtils::HttpsRedirect unless defined &Cpanel::HttpUtils::HttpsRedirect::check_domains_for_https_redirect;    #XXX ugly hack for mock

        #Manually reconstruct what we'd get from WebVhosts
        my @all_domains = ( @{ $res{'sub_domains'} }, @{ $res{'addon_domains'} }, $res{main_domain} );
        my @vhost_cache;
        foreach my $d (@all_domains) {
            push( @vhost_cache, { domain => $d->{servername}, vhost_name => $d->{servername} } );
            foreach my $alias ( split( / /, $d->{serveralias} ) ) {
                push( @vhost_cache, { domain => $alias, vhost_name => $d->{servername} } );
            }
        }

        foreach my $domain (@all_domains) {
            Cpanel::HttpUtils::HttpsRedirect::get_userdata_with_https_redirect_info( $domain->{servername}, $Cpanel::user, $domain, \@vhost_cache );
        }

        $res{parked_with_https_redirects} = [];
        @{ $res{parked_with_https_redirects} } = grep {
            my $rd_dom = $_;
            grep { $_ eq $rd_dom } @{ $res{'parked_domains'} }
        } @{ $domains_hr->{ssl_redirects} };

        $res{parked_capable_of_https_redirects} = [];
        @{ $res{parked_capable_of_https_redirects} } = grep { ref( Cpanel::HttpUtils::HttpsRedirect::check_domains_for_https_redirect( $Cpanel::user, [$_] )->errors() ) ne 'ARRAY' } @{ $res{'parked_domains'} };
    }

    return \%res;
}

# List all the domains associated with an account
#
# returns {
#    'main_domain' => 'foo.com',
#    'sub_domains' => [ 'bar.foo.com', 'baz.foo.com' ],
#    'addon_domains' => [ 'bin.com' ],
# }

sub list_domains {
    my ( $args, $result ) = @_;

    my $domains_hr = _get_domains();
    my @real_subs  = grep { _is_real_sub( $_, $domains_hr->{'addon_domains'} ) } @{ $domains_hr->{'sub_domains'} };
    $domains_hr->{'sub_domains'}   = \@real_subs;
    $domains_hr->{'addon_domains'} = [ keys %{ $domains_hr->{'addon_domains'} } ];

    $result->data($domains_hr);

    return 1;
}

# returns 1 or 0 if a domain is a real subdomain or not
# used to support list_all_domains
sub _is_real_sub {
    my ( $sub, $addon_hr ) = @_;
    if ( grep { $sub eq $_ } values %{$addon_hr} ) {
        return 0;
    }
    return 1;
}

# returns the contents from /var/cpanel/userdata/$username/$domain for a domain
# Optionally return information as to whether it can/is setup for HTTPS redirects
#
# returns a hashref consisting of this data
sub single_domain_data {
    my ( $args, $result ) = @_;

    my ($domain) = $args->get('domain');

    $locale ||= Cpanel::Locale->get_handle();

    if ( !defined $domain ) {
        $result->raw_error( $locale->maketext('Domain must be passed as a parameter.') );
        return;
    }

    my $_domains = _get_domains();

    my $domain_data;

    if ( exists $_domains->{'addon_domains'}->{$domain} ) {

        # If it's an addon domain, modify & return the hasref for the associated sub_domain
        $domain_data = _get_domains_info_hr( $_domains->{'addon_domains'}->{$domain}, 'addon_domain' ), $domain_data->{'domain'} = $domain;
    }
    else {
        $domain_data = _get_domains_info_hr( $domain, 'sub_domain' );

        # if we are unable to find the domain...
        if ( !$domain_data ) {
            $result->raw_error( $locale->maketext( "Unable to locate the domain: [_1]", $domain ) );
            return;
        }

    }

    if ( $args->get('return_https_redirect_status') ) {

        #Then I need to set can_https_redirect and is_https_redirecting
        require Cpanel::HttpUtils::HttpsRedirect unless defined &Cpanel::HttpUtils::HttpsRedirect::check_domains_for_https_redirect;    #XXX ugly hack for mock
        Cpanel::HttpUtils::HttpsRedirect::get_userdata_with_https_redirect_info( $domain, $Cpanel::user, $domain_data );
    }

    if ( $_domains->{'main_domain'} eq $domain ) {
        $domain_data->{'type'} = 'main_domain';
    }

    $result->data($domain_data);

    return 1;
}

# Get the information for a domain
#
# parameters:
#   $domain_name - string - the domain name to grab info for
#   $type - enum - The "type" pf domain e.g. 'main_domain', 'addon_domain', 'sub_domain'
#
# returns:
#   The contents of /var/cpanel/userdata/$username/$username deserialized into a hasref
sub _get_domains_info_hr {
    my ( $domain, $type ) = @_;

    #
    # Warning: We are modifing data without making a copy
    # here.  This relys on the legacy behavior of fetch_ref
    # in Cpanel::CachedDataStore which is the underlying
    # code for Cpanel::Config::userdata::Load::load_*
    #
    my $userdata = Cpanel::Config::userdata::Load::load_userdata( $Cpanel::user, $domain );

    if ( !keys %{$userdata} ) {
        return 0;
    }

    $userdata->{'domain'} = $domain;
    $userdata->{'type'}   = $type;     # this is here so that we have context when returning a 'flat' dataset

    #Get redirect info so we can use this on the domains page rather than 4 separate calls
    my ($status) = Cpanel::HttpUtils::Htaccess::getrewriteinfo( $userdata->{documentroot}, $domain, time() );
    $status =~ s/\%\{REQUEST_URI\}/\//g;
    $userdata->{'status'} = $status;

    return $userdata;
}

1;
