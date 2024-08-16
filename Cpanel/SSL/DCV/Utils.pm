package Cpanel::SSL::DCV::Utils;

# cpanel - Cpanel/SSL/DCV/Utils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::Utils

=head1 SYNOPSIS

    my ($http_ar, $dns_ar) = dcv_method_hash_to_http_and_dns( $domain_dcv_method_hr );

=cut

use Cpanel::Context   ();
use Cpanel::Exception ();

=head1 FUNCTIONS

=head2 dcv_method_hash_to_http_and_dns( DOMAIN_DCV_METHOD_HR )

This takes a hash of ( domain => dcv_method ) and returns
two array references: one of the C<http> domains, and one of the
C<dns> domains. (The arrays can be empty.)

Any unrecognized DCV methods will cause an exception to be thrown.

If cP/WHM ever introduces an additional DCV method (i.e., beyond HTTP
and DNS), the return from this function will likely just add another
array reference.

=cut

sub dcv_method_hash_to_http_and_dns {
    my ($domain_dcv_method_hr) = @_;

    Cpanel::Context::must_be_list();

    die Cpanel::Exception::create_raw( 'MissingParameter', 'Need “domain_dcv_method”' ) if !$domain_dcv_method_hr;

    my $lists_hr = _dcv_method_hash_to_method_lists($domain_dcv_method_hr);

    my ( $http_domains_ar, $dns_domains_ar ) = delete @{$lists_hr}{ 'http', 'dns' };

    if (%$lists_hr) {

        # Just pick a method and domain.
        my $method = (%$lists_hr)[0];
        my $domain = $lists_hr->{$method}[0];
        die Cpanel::Exception->create_raw("Unknown DCV method for “$domain”: “$method”");
    }

    $_ //= [] for ( $http_domains_ar, $dns_domains_ar );

    return ( $http_domains_ar, $dns_domains_ar );
}

sub _dcv_method_hash_to_method_lists {
    my ($domain_dcv_method_hr) = @_;

    my %method_list;

    for my $domain ( keys %$domain_dcv_method_hr ) {
        my $method = $domain_dcv_method_hr->{$domain};

        #Take advantage of auto-vivification …
        push @{ $method_list{$method} }, $domain;
    }

    return \%method_list;
}

1;
