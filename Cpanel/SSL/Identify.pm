package Cpanel::SSL::Identify;

# cpanel - Cpanel/SSL/Identify.pm                   Copyright 2023 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Identify

=head1 DESCRIPTION

Logic to tell whether a given certificate is a free cPanel-branded
certificate or not.

=head1 FUNCTIONS

=head2 $yn = is_free_hostname_cert( $CERT_OBJ )

Returns a boolean to indicate whether a certificate is a free
cPanel-branded hostname certificate.

B<IMPORTANT:> As of v98, new hostname certs are just 90-day cPanel certs.
(The same ones L<Cpanel::SSL::Auto::Provider::cPanel> provisions.)
See C<is_parsed_free_cpanel_90_day_cert> for the appropriate logic
to use to identify those. We still need to retain this logic, though, as
long as we have boxes that may still use the old 1-year hostname certs
that may update to v98+.

$CERT_OBJ is a L<Cpanel::SSL::Objects::Certificate> instance.

=cut

sub is_free_cpanel_hostname_cert ($installed_certificate) {

    my $parse = $installed_certificate->parsed();
    #
    # Free Hostname certs have an issuer of 'cPanel, Inc. Certification Authority' or 'cPanel, LLC. Certification Authority' or similar
    # Never have wildcard domains
    # and only have two domains (hostname, www.hostname);
    # valid for at last 365 days
    #
    return 0 if scalar @{ $parse->{'domains'} } > 2;

    return 0 if grep { tr{*}{} } @{ $parse->{'domains'} };

    return 0 unless _issuer_is_cpanel($parse);
    my $validity = 1 + $parse->{'not_after'} - $parse->{'not_before'};

    # hostname certs are valid for at least one year.
    return 0 if $validity < ( 365 * 86400 );

    # Hostname certs are never valid for much more than one year.
    # As of late 2018 Sectigo sets start/end validity times for midnight
    # UTC, so there is often up to a day’s “extra” added on for that,
    # and there can be leap years, so we’re at 367 days of validity.
    # Add one day for “padding” just in case, and we’re at 368.
    return 0 if $validity > ( 368 * 86400 );

    # hostname certs are always DV
    return 0 if $parse->{'validation_type'} ne 'dv';

    # At this point its very likely a free hostname cert
    # unless they bought one from cPanel, Inc. Certification Authority for a
    # a one year period and installed it on the hostname.   Not sure why
    # they would do that if they have free hostname certs on.
    #
    return 1;
}

=head2 $yn = is_free_cpanel_90_day_cert( $CERT_OBJ )

Returns a boolean to indicate whether a certificate is a free
cPanel-branded 90-day certificate.

$CERT_OBJ is a L<Cpanel::SSL::Objects::Certificate> instance.

=cut

sub is_free_cpanel_90_day_cert ($certificate) {
    return is_parsed_free_cpanel_90_day_cert( $certificate->parsed() );
}

=head2 $yn = is_free_cpanel_90_day_cert( $PARSED )

Returns a boolean to indicate whether a certificate is a free
cPanel-branded 90-day certificate.

$PARSED is the output of, e.g., L<Cpanel::SSL::Utils>’s
C<parse_certificate_text()>.

=cut

sub is_parsed_free_cpanel_90_day_cert ($parse) {

    return 0 unless _issuer_is_cpanel($parse);
    my $validity = 1 + $parse->{'not_after'} - $parse->{'not_before'};

    #Sectigo actually issues 91-day certificates in response to
    #our requests for 90-day certificates. To be on the safe side of
    #accommodating any such wrinkles we might find later, let’s assume
    #that anything valid for under 100 days is one of our freebie certs.
    return 0 if $validity > ( 100 * 86400 );
    return 1;
}

sub _issuer_is_cpanel ($parse) {
    return 0 if !length $parse->{'issuer'}{'commonName'};
    return 0 if $parse->{'issuer'}{'commonName'} !~ m/cPanel.*(Inc\.|L\.?L\.?C\.?).*Certificat.*Authority/i;
    return 1;
}

1;
