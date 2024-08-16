package Cpanel::SSL::DynamicDNSCheck;

# cpanel - Cpanel/SSL/DynamicDNSCheck.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DynamicDNSCheck

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

This module implements a check of the TLS state for dynamic DNS subdomains.
It’s a counterpart to L<Cpanel::SSL::VhostCheck>.

Note that, unlike local services, dynamic DNS domains are understood B<NOT>
to be local to the cPanel & WHM server. As a result, this module doesn’t
investigate an “installed” certificate; instead, it checks the user’s
SSLStorage. (cf. L<Cpanel::SSLStorage::User>)

=cut

#----------------------------------------------------------------------

use Crypt::Format ();

use Cpanel::Context                    ();
use Cpanel::SSL::CABundleCache         ();
use Cpanel::SSL::DefaultKey::User      ();
use Cpanel::SSL::DynamicDNSCheck::Item ();
use Cpanel::SSL::Objects::Certificate  ();
use Cpanel::SSL::Verify                ();
use Cpanel::SSLStorage::User           ();
use Cpanel::WebCalls::Datastore::Read  ();

# The bigger this value is, the more frequently we ask users to
# replace their certificates. But the lower this value is, the less
# time we give users to do that certificate replacement before an
# existing certificate expires. So we want a nice “middle ground”.
#
my $VALIDITY_PADDING_DAYS = 15;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 @report = get_report_for_user( $USERNAME )

Returns a list of L<Cpanel::SSL::DynamicDNSCheck::Item> instances,
one for each dynamic DNS subdomain.

=cut

sub get_report_for_user ($username) {
    Cpanel::Context::must_be_list();

    my @ddns = values %{ Cpanel::WebCalls::Datastore::Read->read_for_user($username) };
    @ddns = grep { $_->isa('Cpanel::WebCalls::Entry::DynamicDNS') } @ddns;

    my @results;

    if (@ddns) {

        # Sort for a predictable order:
        my @domains = sort map { $_->domain() } @ddns;

        my ( $ok, $sslstorage ) = Cpanel::SSLStorage::User->new( user => $username );
        die $sslstorage if !$ok;

        my $verifier = Cpanel::SSL::Verify->new();

        my $want_key_type = Cpanel::SSL::DefaultKey::User::get($username);

        for my $domain (@domains) {

            # We don’t want just *any* certificate; we want a certificate
            # that matches *only* this domain. So searching on subject.CN
            # is legit, since as of September 2020 all CAs still populate
            # that field.
            #
            my ( $ok, $certs ) = $sslstorage->find_certificates( 'subject.commonName' => $domain );
            die "find $domain certificates: $certs" if !$ok;

            my $usable_cert;

          CERT:
            for my $cert_hr (@$certs) {
                my $cert_pem;

                ( $ok, $cert_pem ) = $sslstorage->get_certificate_text($cert_hr);
                die "get $cert_hr->{'id'} cert: $cert_pem" if !$ok;

                my $cert_obj = Cpanel::SSL::Objects::Certificate->new( cert => $cert_pem );

                # Reject weak keys & signatures:
                next CERT if !$cert_obj->key_is_strong_enough();
                next CERT if !$cert_obj->signature_algorithm_is_strong_enough();

                # Reject key types that mismatch user’s preference:
                next CERT if $want_key_type ne $cert_obj->key_type();

                my $url = $cert_obj->caIssuers_url();
                next CERT if !$url;

                my $cab_blob = Cpanel::SSL::CABundleCache->load($url);

                my @cab = Crypt::Format::split_pem_chain($cab_blob);

                my $verified = $verifier->verify( $cert_pem, @cab );

                next CERT if !$verified->ok();

                # Cert passes local verification.
                # Now check for revocation via OCSP.
                next CERT if $cert_obj->revoked($cab_blob);

                # Cert is valid & not confirmed-revoked.
                # Now check to see if it’s close enough to expiration
                # to justify bugging the user to update their certificate.
                #next CERT if Cpanel::SSL::CheckCommon::get_expiration_problems($cert_obj, $VALIDITY_PADDING_DAYS);

                # Great success! No need to fetch a new certificate.
                $usable_cert = $cert_obj;

                last;
            }

            my %item = (
                domain      => $domain,
                certificate => $usable_cert,
            );

            push @results, Cpanel::SSL::DynamicDNSCheck::Item->adopt( \%item );
        }
    }

    return @results;
}

1;
