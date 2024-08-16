package Cpanel::SSL::Objects::Certificate;

# cpanel - Cpanel/SSL/Objects/Certificate.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Crypt::Algorithm ();
use Cpanel::Crypt::Constants ();    # PPI NO PARSE - cf. CPANEL-33799
use Cpanel::Exception        ();
use Cpanel::PEM              ();

our $VERSION = '1.5';               # never end in zero for Cpanel::SSL::Objects::Certificate::File

use Try::Tiny;

my $locale;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Objects::Certificate - An object that represents an X509 certificate.

=head1 FUNCTIONS

=cut

sub new {
    my ( $class, %OPTS ) = @_;

    my $cert = $OPTS{'cert'};

    die 'Missing “cert”!' if !$cert;

    my $parsed = _parse_pem_or_die($cert);

    return $class->new_from_parsed_and_text( $parsed, $cert );
}

sub _parse_pem_or_die ($pem) {
    require Cpanel::SSL::Utils;
    my ( $ok, $parsed ) = Cpanel::SSL::Utils::parse_certificate_text($pem);
    if ( !$ok ) {
        _get_locale();
        die $locale->maketext( 'The system could not parse the certificate because of an error: [_1]', $parsed ) . "\n";
    }

    return $parsed;
}

sub new_from_parsed_and_text {
    my ( $class, $parsed, $text ) = @_;
    if ( !$parsed->{'subject'} ) {
        _get_locale();
        die $locale->maketext('The certificate is not complete.') . "\n";
    }

    return bless {
        parsed       => $parsed,
        subject_text => join( "\n", map { @$_ } @{ $parsed->{'subject_list'} } ),
        issuer_text  => join( "\n", map { @$_ } @{ $parsed->{'issuer_list'} } ),
        text         => $text,
        _VERSION     => $VERSION,
    }, $class;
}

sub subject_text {
    my ($self) = @_;

    return $self->{'subject_text'};
}

sub issuer_text {
    my ($self) = @_;
    return $self->{'issuer_text'};
}

sub text {
    my ($self) = @_;
    return $self->{'text'};
}

sub signature_algorithm {
    my ($self) = @_;
    return $self->{'parsed'}{'signature_algorithm'};
}

sub validation_type {
    my ($self) = @_;
    return $self->{'parsed'}{'validation_type'};
}

# NB: This logic might more gainfully be rewritten to:
#   1. Parse out the key’s “security bits”. (cf. EVP_PKEY_security_bits(3))
#   2. Determine OpenSSL’s default security level.
#      i.e., CTX_get_security_level( CTX_new() )
#   3. Determine the minimum security bits for that security level.
#   4. Compare the two security-bits numbers.
#
# Security bits and levels are new in OpenSSL 1.1.0, though, so we would
# still need the existing logic for RH7-era OSes.
#
sub key_is_strong_enough {
    my ($self) = @_;

    my $ret;

    local ( $@, $! );

    Cpanel::Crypt::Algorithm::dispatch_from_object(
        $self,
        rsa => sub {
            require Cpanel::RSA::Constants;
            $ret = ( $self->{'parsed'}{'modulus_length'} >= $Cpanel::RSA::Constants::DEFAULT_KEY_SIZE ? 1 : 0 );
        },
        ecdsa => sub {
            require Cpanel::Crypt::ECDSA::Data;

            # There’s no point in just returning 0; anything that we don’t
            # allow should, at least for now, never get here.
            if ( !Cpanel::Crypt::ECDSA::Data::curve_name_is_valid( $self->{'parsed'}{'ecdsa_curve_name'} ) ) {
                die "Unknown ECDSA curve: “$self->{'parsed'}{'ecdsa_curve_name'}”";
            }

            $ret = 1;
        },
    );

    return $ret;
}

sub verify_key_is_strong_enough {
    my ($self) = @_;

    if ( !$self->key_is_strong_enough() ) {
        local ( $@, $! );
        require Cpanel::RSA::Constants;
        die Cpanel::Exception->create( 'This key uses [numf,_1]-bit [asis,RSA] encryption, which is too weak to provide adequate security. Use an [asis,ECDSA] key, or use an [asis,RSA] key with at least [numf,_2]-bit encryption.', [ $self->{'parsed'}{'modulus_length'}, $Cpanel::RSA::Constants::DEFAULT_KEY_SIZE ] );
    }

    return;
}

=head2 has_subject_alt_name

This is a convenience function that checks to see if there is at least one label present in the subjectAltName (2.5.29.17) data.

=cut

sub has_subject_alt_name {
    my ($self) = @_;
    return ( $self->{'parsed'}{'extensions'}{'subjectAltName'} && $self->{'parsed'}{'extensions'}{'subjectAltName'}{'value'} && scalar @{ $self->{'parsed'}{'extensions'}{'subjectAltName'}{'value'} } )
      ? 1
      : 0;
}

=head2 has_server_auth_in_extended_key_usage_extension

This is a convenience function that checks to see if the ExtendedKeyUsage (OID) contains serverAuth

=cut

sub has_server_auth_in_extended_key_usage_extension {
    my ($self) = @_;
    return ( $self->{'parsed'}{'extensions'}{'extendedKeyUsage'} && $self->{'parsed'}{'extensions'}{'extendedKeyUsage'}{'value'} && $self->{'parsed'}{'extensions'}{'extendedKeyUsage'}{'value'}{'serverAuth'} )
      ? 1
      : 0;
}

sub signature_algorithm_is_strong_enough {
    my ($self) = @_;

    require Cpanel::SSL::Utils;
    my $comparison_val = Cpanel::SSL::Utils::hashing_function_strength_comparison(
        $self->signature_algorithm(),
        _minimum_permitted_signature_algorithm()
    );

    return ( $comparison_val > -1 ) ? 1 : 0;
}

sub verify_signature_algorithm_is_strong_enough {
    my ($self) = @_;

    if ( !$self->signature_algorithm_is_strong_enough() ) {

        die Cpanel::Exception->create( 'This certificate’s signature algorithm ([_1]) is too weak. The weakest permissible algorithm is “[_2]”.', [ $self->signature_algorithm(), _minimum_permitted_signature_algorithm() ] );
    }

    return;
}

sub OCSP {
    my ($self) = @_;
    return $self->{'parsed'}{'extensions'}{'OCSP'}{'value'};
}

#i.e., given a timestamp, is the certificate expired at that point?
sub is_expired_at {
    my ( $self, $time ) = @_;
    return ( $time > $self->{'parsed'}{'not_after'} ) ? 1 : 0;
}

sub _time {    # for mocking
    return time();
}

sub expired {
    my ($self) = @_;
    return $self->is_expired_at( _time() );
}

# valid_for_any_local_domain checks to see if any domain on the certificate
# is configured and pointed to this server
sub valid_for_any_local_domain {
    my ($self) = @_;
    return $self->{'_valid_for_any_local_domain'} if defined $self->{'_valid_for_any_local_domain'};
    require Cpanel::Config::LoadUserDomains;
    require Cpanel::SSL::Utils;
    $self->{'_valid_for_any_local_domain'} = 0;

    # Previously this incorrectly checked against /etc/localdomains which is
    # a list of EMAIL local domains.  This check is intended to tell if a domain
    # is configured and pointed to this server.  It is not intended to check how
    # email delivery is configured.
    my $domain_to_user_map = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
    my @all_server_domains = keys %$domain_to_user_map;
    my $cert_domains_ar    = $self->domains();

    if ( Cpanel::SSL::Utils::validate_domains_lists_have_match( $cert_domains_ar, \@all_server_domains ) ) {
        return ( $self->{'_valid_for_any_local_domain'} = 1 );
    }
    return $self->{'_valid_for_any_local_domain'};
}

# As of v72, this assumes that $cab_pem is ORDERED.
# If there is no $cab_pem, then we attempt to fetch one.
#
# Returns:
#   1 - The certificate is revoked
#   0 - The certificate is not revoked
#   undef - We do not know the revocation state of the certificate
sub revoked {
    my ( $self, $cab_pem ) = @_;

    return $self->{'_revoked'} if exists $self->{'_revoked'};

    if ( !$self->{'parsed'}{'is_self_signed'} && !$self->expired() && $self->OCSP() ) {
        require Cpanel::SSL::OCSP;

        # We will need to cache this based on the parsed cert id
        # If OCSP is broken we assume the that the certificate is not
        # revoked
        try {
            if ($cab_pem) {
                $self->{'_revoked'} = Cpanel::SSL::OCSP::cert_chain_is_revoked( $self->OCSP(), $self->{'text'}, Cpanel::PEM::split($cab_pem) );
            }
            else {
                $self->{'_revoked'} = Cpanel::SSL::OCSP::cert_is_revoked( $self->{'text'}, $self->OCSP() );
            }
        }
        catch {
            local $@ = $_;
            warn;
        };
    }

    return $self->{'_revoked'};
}

#
# provided for your convenience
#
sub has_private_key_in_sslstorage {
    my ($self) = @_;

    require Cpanel::SSLStorage::User;
    my $storage = Cpanel::SSLStorage::User->new();

    my ( $ok, $key_hr ) = $storage->find_key_for_object($self);

    if ( !$ok ) {
        warn "Failed to find key in SSLStorage: $key_hr";
        return undef;
    }

    return $key_hr ? 1 : 0;
}

sub valid_for_domain {
    my ( $self, $domain ) = @_;
    return $self->{'_valid_for_domain'}{$domain} if defined $self->{'_valid_for_domain'}{$domain};
    require Cpanel::SSL::Utils;
    $self->{'_valid_for_domain'}{$domain} = Cpanel::SSL::Utils::validate_domains_lists_have_match( $self->{'parsed'}{'domains'}, $domain );
    return ( $self->{'_valid_for_domain'}{$domain} ||= 0 );
}

sub find_domains_lists_matches {
    my ( $self, $domains_ar ) = @_;
    require Cpanel::SSL::Utils;
    return Cpanel::SSL::Utils::find_domains_lists_matches( $self->{'parsed'}{'domains'}, $domains_ar );
}

sub parsed {
    my ($self) = @_;
    return $self->{'parsed'};
}

sub not_before {
    my ($self) = @_;
    return $self->{'parsed'}{'not_before'};
}

sub not_after {
    my ($self) = @_;
    return $self->{'parsed'}{'not_after'};
}

sub signature {
    my ($self) = @_;
    return $self->{'parsed'}{'signature'};
}

sub is_self_signed {
    my ($self) = @_;
    return $self->{'parsed'}{'is_self_signed'};
}

sub issuer {
    my ($self) = @_;
    return { %{ $self->{'parsed'}{'issuer'} } };
}

sub issuer_list {
    my ($self) = @_;
    return [ map { [@$_] } @{ $self->{'parsed'}{'issuer_list'} } ];
}

sub subject_list {
    my ($self) = @_;
    return [ map { [@$_] } @{ $self->{'parsed'}{'subject_list'} } ];
}

=head2 $alg = I<OBJ>->key_algorithm()

Returns one of the C<ALGORITHM_*> constants from
L<Cpanel::Crypt::Constants>.

=cut

sub key_algorithm ($self) {

    # Caches from pre-92 won’t have this value in the parse,
    # but they’ll also all be RSA.
    return $self->{'parsed'}{'key_algorithm'} // Cpanel::Crypt::Constants::ALGORITHM_RSA;
}

=head2 $type = I<OBJ>->key_type()

Returns a string that indicates the key algorithm as well as the
encryption strength. Specifically, the return will be one of:

=over

=item * C<rsa-$modulus_length>

=item * C<ecdsa-$curve_name>

=back

Note that these are compatible with C<OPTIONS> from
L<Cpanel::SSL::DefaultKey::Constants>.

=cut

sub key_type ($self) {
    local ( $@, $! );
    require Cpanel::Crypt::Algorithm;

    return Cpanel::Crypt::Algorithm::dispatch_from_object(
        $self,
        rsa => sub ($self) {
            return 'rsa-' . $self->modulus_length();
        },
        ecdsa => sub ($self) {
            return 'ecdsa-' . $self->ecdsa_curve_name();
        },
    );
}

#----------------------------------------------------------------------
# RSA-specific logic:
#
sub public_exponent {
    my ($self) = @_;
    return $self->{'parsed'}{'public_exponent'};
}

sub modulus {
    my ($self) = @_;
    return $self->{'parsed'}{'modulus'};
}

sub modulus_length {
    my ($self) = @_;
    return $self->{'parsed'}{'modulus_length'};
}

#----------------------------------------------------------------------
# ECDSA-specific logic:
#
sub ecdsa_curve_name ($self) {
    return $self->{'parsed'}{'ecdsa_curve_name'};
}

sub ecdsa_public ($self) {
    return $self->{'parsed'}{'ecdsa_public'};
}

#----------------------------------------------------------------------

sub domains {
    my ($self) = @_;
    return [ @{ $self->{'parsed'}{'domains'} } ];
}

sub domain {
    my ($self) = @_;
    return $self->{'parsed'}{'subject'}{'commonName'};
}

#----------------------------------------------------------------------

#This returns the “extra” certificates in the file--i.e., those
#that came after the top one. They’re probably the CA bundle, leaf-first.
sub get_extra_certificates {
    require Cpanel::Context;
    Cpanel::Context::must_be_list();

    return $_[0]{'_extra_certs'} ? @{ $_[0]{'_extra_certs'} } : ();
}

sub set_extra_certificates {
    my ( $self, $certs ) = @_;

    $self->{'_extra_certs'} = [ Cpanel::PEM::split($certs) ];
    return 1;
}

sub is_any_extra_certificate_expired_at ( $self, $time ) {
    for my $pem ( $self->get_extra_certificates() ) {
        my $parsed_hr = _parse_pem_or_die($pem);

        return 1 if $time > $parsed_hr->{'not_after'};
    }

    return 0;
}

#----------------------------------------------------------------------

#This is the key for the Cpanel::SSL::CABundleCache repo.
sub caIssuers_url {
    my ($self) = @_;

    my $val = $self->{'parsed'}{'extensions'}{'caIssuers'};
    $val &&= $val->{'value'};

    return $val;
}

#Returns undef if the cert has no link to the next certificate
#up the chain.
sub get_cabundle_pem {
    my ($self) = @_;

    #Might as well cache it
    if ( !$self->{'_cabundle_pem'} ) {
        my $url = $self->caIssuers_url();

        return undef if !$url;

        require Cpanel::SSL::CAIssuers;

        $self->{'_cabundle_pem'} = Cpanel::SSL::CAIssuers::get_cabundle_pem($url);
    }

    return $self->{'_cabundle_pem'};
}

sub _get_locale {
    require Cpanel::Locale;
    return $locale ||= Cpanel::Locale->get_handle();
}

#test expects to overwrite this function
sub _minimum_permitted_signature_algorithm {
    return 'sha224WithRSAEncryption';
}

#cf. openssl/crypto/x509v3/v3_purp.c
#NOTE: Ensure parity between this and base/cjt/ssl.js.
#
#OpenSSL's check_ca() also looks for an old proprietary Netscape
#extension for identifying CA certificates that, as of December 2013,
#appears not to be in use (based on cPanel's collected CA bundles). So we
#don't check for that extension here because there's no way to test that we're
#parsing it correctly.
sub check_ca {
    my ($self) = @_;

    my $exts = $self->{'parsed'}{'extensions'};

    if ($exts) {
        if ( $exts->{'basicConstraints'} ) {
            return $exts->{'basicConstraints'}{'value'}{'cA'} ? 1 : 0;
        }
        elsif ( $exts->{'keyUsage'} ) {
            return $exts->{'keyUsage'}{'value'}{'keyCertSign'} ? 4 : 0;
        }
    }

    #Still necessary for some old root certificates (as of Dec 2013).
    elsif ( $self->{'parsed'}{'is_self_signed'} && ( $self->{'parsed'}{'version'} == 1 ) ) {
        return 3;
    }

    return 0;
}

1;
