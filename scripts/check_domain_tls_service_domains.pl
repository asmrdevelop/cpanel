#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - scripts/check_domain_tls_service_domains.pl
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package scripts::check_domain_tls_service_domains;

=encoding utf-8

=head1 NAME

check_domain_tls_service_domains.pl

=head1 USAGE

    check_domain_tls_service_domains.pl --help

    check_domain_tls_service_domains.pl [--prune] [--verbose]

=head1 DESCRIPTION

When an SSL certificate is installed for an Apache virtual host, the system
copies that certificate into a separate datastore called “Domain TLS”.
Unlike Apache, Domain TLS indexes SSL certificates by FQDN rather than by
virtual host. cPanel-managed SSL services besides Apache match incoming
TLS SNI requests against Domain TLS and, if a match is found, send the
matched certificate to the client in the TLS handshake.

Because most TLS clients nowadays send an SNI string as part of their inital
TLS handshake, most TLS sessions for these services can use a certificate from
Domain TLS.

Domain TLS doesn’t allow installation of expired certificates; however,
certificates in Domain TLS can expire. We generally don’t remove these because
that would cause users to see domain-mismatch warnings; however, for domains
that are secured by service-default certificates (i.e., that are installed via
WHM), we should remove the corresponding Domain TLS entry when the certificate
is about to expire or is otherwise invalid because the service-default
certificate will still cover the domain.

This script executes that check and enforcement, following this logic:

=over

=item Let C<service_certs> be the collection of service-default TLS certificates.

=item Let C<service_domains> be all domains that are on at least one
C<service_certs> certificate.

=item Let C<dtls_domains> be all domains with Domain TLS entries. (This is not
the same as “all domains on all certificates in Domain TLS”; we only care about
the actual FQDN(s) for which a given Domain TLS certificate was installed.)

=item Let C<match_domains> be all C<dtls_domains> that a C<service_domains>
entry completely covers. This EXCLUDES matches between a wildcard
C<dtls_domains> and a non-wildcard C<service_domains>.

=item For each C<match_domains>, verify that the Domain TLS certificate
has at least 25 hours of validity left; if not, print a message. If the
C<--prune> argument was given, delete the Domain TLS entry, and print a
message about it.

=back

The C<--verbose> flag prints extra diagnostic information that you may find
useful.

=head1 CAVEATS

The drawback to this system is that a Domain TLS entry can be removed even
if only one service’s default certificate covers that domain. For this
reason it is strongly recommended that service default certificates all be
the same certificate.

=cut

use strict;
use warnings;

use Try::Tiny;

use parent 'Cpanel::HelpfulScript';

use Cpanel::Domain::TLS                 ();
use Cpanel::Domain::TLS::ServiceOverlap ();
use Cpanel::Domain::TLS::Write          ();
use Cpanel::SSL::Utils                  ();
use Cpanel::SSL::Verify                 ();

#mocked in tests
*_get_service_domains = *Cpanel::Domain::TLS::ServiceOverlap::get_service_domains;

__PACKAGE__->new(@ARGV)->run() if !caller;

use constant _OPTIONS => (
    'prune',
    'verbose',
);

use constant MIN_VALIDITY_LEFT => 86400 + 3600;    #25 hours

sub run {
    my ($self) = @_;

    my @domains_to_verify = $self->_get_service_domains();

    if ( !@domains_to_verify ) {
        if ( $self->getopt('verbose') ) {
            $self->say_maketext('[asis,Domain TLS] has no domains that are on the service default certificates.');
        }

        return;
    }

    if ( $self->getopt('verbose') ) {
        $self->say_maketext( 'The system will check the [asis,Domain TLS] [numerate,_1,entry,entries] for the following [numerate,_1,domain,domains]: [join,~, ,_2]', 0 + @domains_to_verify, \@domains_to_verify );
    }

    my $faulty_count = 0;

    my $verify = Cpanel::SSL::Verify->new();

    for my $domain (@domains_to_verify) {
        my $remove_yn = 0;

        try {
            my @certs = Cpanel::Domain::TLS->get_certificates($domain);

            my $v = $verify->verify(@certs);
            if ( $v->ok() ) {
                my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text( $certs[0] );
                die $parse if !$ok;

                my $validity_left = 1 + $parse->{'not_after'} - time;
                if ( $validity_left < MIN_VALIDITY_LEFT ) {
                    $remove_yn = 1;

                    my @to_say = $self->locale()->maketext( '“[_1]”’s certificate is valid, but it will expire soon.', $domain );

                    if ( $self->getopt('prune') ) {
                        push @to_say, $self->locale()->maketext('The system will remove the certificate now to ensure that no client receives it after it expires.');
                    }
                    else {
                        push @to_say, $self->bold( $self->locale()->maketext('This certificate should be removed or replaced.') );
                    }

                    $self->say( join( ' ', @to_say ) );
                }
                elsif ( $self->getopt('verbose') ) {
                    $self->say_maketext( '“[_1]”’s certificate is valid.', $domain );
                }
            }
            else {
                $self->say_maketext( '“[_1]”’s certificate failed validation: [_2]', $domain, $v->get_error_string() );

                $remove_yn = 1;
            }

            if ($remove_yn) {
                $faulty_count++;

                if ( $self->getopt('prune') ) {
                    Cpanel::Domain::TLS::Write->enqueue_unset_tls($domain);

                    #Technically this is no longer true; the certificate
                    #still exists until we reap Domain TLS’s unset queue.
                    $self->say_maketext( '“[_1]”’s certificate is removed. Non-[asis,HTTP] services will no longer use this certificate.', $domain );
                }
            }
        }
        catch {
            warn "An error occurred while checking “$domain”’s certificate: $_";
        };
    }

    if ( $faulty_count && !$self->getopt('prune') ) {
        $self->say(q<>);
        $self->say_maketext( '[quant,_1,domain has a certificate,domains have certificates] that should be removed or replaced. Run the following command to do this:', $faulty_count );
        $self->say(q<>);
        $self->say( $self->bold("$0 --prune") );
    }

    return;
}

1;
