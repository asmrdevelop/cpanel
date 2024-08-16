package Cpanel::Domain::TLS::ServiceOverlap;

# cpanel - Cpanel/Domain/TLS/ServiceOverlap.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Domain::TLS::ServiceOverlap

=head1 SYNOPSIS

    my @domains = Cpanel::Domain::TLS::ServiceOverlap::get_service_domains();

=head1 DESCRIPTION

Logic for comparing TLS coverage between Domain TLS and service default
certificates.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Context              ();
use Cpanel::Domain::TLS          ();
use Cpanel::SSL::Utils           ();
use Cpanel::SSLCerts             ();
use Cpanel::WildcardDomain       ();
use Cpanel::WildcardDomain::Tiny ();

#As of v66 there is no SNI support for FTP; hopefully that will change
#now that ProFTPD supports it easily.
use constant _SKIP_SERVICES => ( 'ftp', 'mail_apns' );

=head2 my @domains = get_service_domains();

This returns a list of all Domain TLS entries that at least one service’s
default TLS certificate covers completely. Examples:

=over

=item YES: Domain TLS for C<example.com> when service certificate
includes the same domain.

=item YES: Domain TLS for C<foo.example.com> when service certificate
includes C<*.example.com>.

=item YES: Domain TLS for C<*.example.com> when service certificate
includes C<*.example.com>.

=item B<NO>: Domain TLS for C<*.example.com> when service certificate
includes C<foo.example.com>.

This last example is not included because the service certificate doesn’t
B<completely> cover the same domain coverage as the Domain TLS certificate.

=back

The application for this list of domains is to re-verify the Domain TLS
entries for each domain and to remove any invalid Domain TLS entries. This
prevents users from seeing TLS warnings when a perfectly good and valid
service-default certificate can cover the relevant domain(s).

=cut

sub get_service_domains {
    my ($self) = @_;

    Cpanel::Context::must_be_list();

    my %service_non_wc_domains;
    my %service_wc_domains;
    for my $svc ( keys %{ Cpanel::SSLCerts::rSERVICES() } ) {
        try {
            if ( grep { $_ eq $svc } _SKIP_SERVICES() ) {
                my $pem = _get_service_cert_pem($svc);

                my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text($pem);
                if ( !$ok ) {
                    die "Ignoring missing certificate for $svc.\n" unless defined $parse;
                    die "$svc parse error: $parse";
                }

                for my $domain ( @{ $parse->{'domains'} } ) {
                    if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($domain) ) {
                        $service_wc_domains{$domain} = ();
                    }
                    else {
                        $service_non_wc_domains{$domain} = ();
                    }
                }
            }
        }
        catch { warn $_ };
    }

    for my $wc ( keys %service_wc_domains ) {
        my @matching_non_wc = grep { Cpanel::WildcardDomain::wildcard_domains_match( $_, $wc ) } keys %service_non_wc_domains;
        delete @service_non_wc_domains{@matching_non_wc};
    }

    my @domains_to_verify = ( keys(%service_non_wc_domains), keys(%service_wc_domains) );

    #This hash contains all of the Domain TLS domains
    #that a service cert also covers.
    my %service_union_dtls_domains;
    @service_union_dtls_domains{ grep { Cpanel::Domain::TLS->has_tls($_) } @domains_to_verify } = ();

    #If there are any wildcards on the service certs, then we also check
    #Domain TLS entries that match the wildcards. We need any wildcard-matches
    #between Domain TLS and the service wildcard domains.
    if (%service_wc_domains) {
        for my $svc_domain ( keys %service_wc_domains ) {
            @service_union_dtls_domains{ grep { Cpanel::WildcardDomain::wildcard_domains_match( $_, $svc_domain ) } Cpanel::Domain::TLS->get_tls_domains() } = ();
        }
    }

    #array is to satisfy Perl::Critic
    return @{ [ sort keys %service_union_dtls_domains ] };
}

sub _get_service_cert_pem {
    my ($svc) = @_;

    my $tls_info = Cpanel::SSLCerts::fetchSSLFiles( service => $svc );

    return $tls_info->{'crt'};
}

1;
