package Cpanel::SSL::Create;

# cpanel - Cpanel/SSL/Create.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Create - creation logic for SSL components

=head1 SYNOPSIS

For the common case of just needing a CSR for a given list of domains:

    use Cpanel::SSL::Create ();

    my $csr_pem = Cpanel::SSL::Create::csr_with_domains(
        $key_pem,
        @domains,
    );

… or, for the more general case of arbitrary subject/SAN entries:

    my $csr_pem = Cpanel::SSL::Create::csr(
        key => $key_pem,
        subject_names => [
            [ dNSName => 'foo.com' ],
            [ dNSName => 'bar.tld' ],
        ],
        subject => [
            [ organizationName => 'cPanel, Inc.' ],
            [ localityName => 'Houston' ],
            [ stateOrProvinceName => 'TX' ],
        ],
    );

=head1 DESCRIPTION

Fork to the C<openssl> binary?!?! Pah! :) Use this module
for more reliable generation of SSL components.

=head1 SEE ALSO

L<Cpanel::RSA> - generation of RSA keys

L<Cpanel::Crypt::ECDSA::Generate> - generation of ECDSA keys

=cut

use Crypt::Perl::PK     ();
use Crypt::Perl::PKCS10 ();

use Cpanel::Exception      ();
use Cpanel::SSL::Constants ();
use Cpanel::UTF8::Strict   ();

#cf. OpenSSL:
#   crypto/x509v3/v3_alt.c
#   crypto/x509v3/v3_genn.c
my %subject_name_type_to_conf = qw(
  dNSName     DNS
  rfc822Name  email
);

# From RFC3280, these values are hard coded into openssl
# #define ub_common_name                  64
# https://tools.ietf.org/html/rfc5280#appendix-A.1
my %MAX_LENGTH = (
    'CN'         => Cpanel::SSL::Constants::MAX_CN_LENGTH(),
    'commonName' => Cpanel::SSL::Constants::MAX_CN_LENGTH(),
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $pem = csr( %OPTS )

Generates a CSR and returns it in PEM format.

%OPTS are:

=over

=item * C<subject_names> - required, arrayref of arrayrefs (type => name),
e.g.:

    [
        [ dNSName => 'foo.tld' ],
        ...
    ]

=item * C<key> - required, PEM

=item * C<subject> - optional, arrayref of arrayrefs (type => name),
e.g.:

    [
        [ localityName => 'Houston' ],
        ...
    ]

=back

=cut

sub csr {
    my %opts = @_;

    die "Need “subject_names” arrayref!" if ref( $opts{'subject_names'} ) ne 'ARRAY';
    die "Need “key”!"                    if !$opts{'key'};

    my $prkey = Crypt::Perl::PK::parse_key( $opts{'key'} );

    my @subject_kv;

    for my $dn_ar ( @{ $opts{'subject'} } ) {
        my ( $k, $v ) = @$dn_ar;

        if ( exists $MAX_LENGTH{$k} && length $v > $MAX_LENGTH{$k} ) {
            die Cpanel::Exception::create( 'TooManyBytes', [ value => $v, maxlength => $MAX_LENGTH{$k}, key => $k ] );
        }

        # Crypt::Perl expects character strings.
        Cpanel::UTF8::Strict::decode($v);

        push @subject_kv, $k => $v;
    }

    # Ideally we’d use OpenSSL rather than (the MUCH slower) Crypt::Perl,
    # but as of this writing Crypt::OpenSSL::PKCS10 can’t grok ECDSA.
    # It probably wouldn’t be hard to add if that’s necessary.
    my $pkcs10 = Crypt::Perl::PKCS10->new(
        key => $prkey,

        subject => \@subject_kv,

        attributes => [
            [
                'extensionRequest',
                [
                    'subjectAltName',
                    map { @$_ } @{ $opts{'subject_names'} },
                ],
            ],
        ],
    );

    my $pem = $pkcs10->to_pem();

    return ( $pem =~ s<\s+\z><>r );
}

=head2 $pem = csr_with_domains( $KEY_PEM, @DOMAINS )

A convenience wrapper around C<csr()> that generates a bare-bones
CSR for a list of @DOMAINS.

=cut

sub csr_with_domains ( $key, @domains ) {

    return Cpanel::SSL::Create::csr(
        subject_names => [ map { [ dNSName => $_ ] } @domains ],
        key           => $key,
        subject       => [
            [ commonName => $domains[0] ],
        ],
    );
}

=head2 $pem = csr_single_domain( $KEY_PEM, $DOMAIN )

Like C<csr_with_domains()> but only accepts a single domain.
Not very useful anymore; this is only here for backward compatibility.

=cut

sub csr_single_domain ( $key, $domain ) {

    return csr_with_domains( $key, $domain );
}

=head2 $pem = key( $TYPE )

Generates a key of the specified $TYPE, which must be one
of the C<Cpanel::SSL::DefaultKey::Constants::OPTIONS>.

=cut

sub key ($type) {
    require Cpanel::SSL::DefaultKey;

    if ( !Cpanel::SSL::DefaultKey::is_valid_value($type) ) {
        die "invalid type: $type";
    }

    my ( $alg, $detail ) = split m<->, $type;

    local ( $@, $! );

    if ( $alg eq 'rsa' ) {
        require Cpanel::RSA;

        # $detail is the modulus length (in bits)
        return Cpanel::RSA::generate_private_key_string($detail);
    }

    if ( $alg eq 'ecdsa' ) {
        require Cpanel::Crypt::ECDSA::Generate;

        # $detail is the curve name
        return Cpanel::Crypt::ECDSA::Generate::pem($detail);
    }

    die "Invalid key type: $type";
}

1;
