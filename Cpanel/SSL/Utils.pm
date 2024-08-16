package Cpanel::SSL::Utils;

# cpanel - Cpanel/SSL/Utils.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Context                  ();
use Cpanel::Crypt::Algorithm         ();
use Cpanel::Crypt::Constants         ();
use Cpanel::Base64                   ();
use Cpanel::Crypt::ECDSA::Data       ();
use MIME::Base64                     ();
use Cpanel::WildcardDomain           ();
use Cpanel::Encoder::utf8            ();
use Cpanel::Exception                ();
use Cpanel::PEM                      ();
use Cpanel::SSL::Parsed::Certificate ();
use Cpanel::SSL::Parsed::Key         ();
use Cpanel::SSL::Parsed::CSR         ();

BEGIN {
    *normalize = *Cpanel::PEM::strip_pem_formatting;
}

our $MAX_OBJECTS_IN_CACHE = 256;

our $EV_CACHE_FILE = '/usr/local/cpanel/etc/x509_ev_issuers.json';

my $_BASE64_CHAR = '[a-zA-Z0-9/+=]';
our $_BASE64_CHAR_SPACES = $_BASE64_CHAR . '[a-zA-Z0-9/+=\s]+' . $_BASE64_CHAR;

#These are in the order in which the components appear in an RSA key file.
my @RSA_ORDER = qw(
  modulus
  public_exponent
  private_exponent
  prime1
  prime2
  exponent1
  exponent2
  coefficient
);

my @HASHING_FUNCTION_STRENGTH_ORDER = (
    'none',
    'md5WithRSAEncryption',
    'sha1WithRSAEncryption',

    'sha224WithRSAEncryption',
    'ecdsa-with-SHA224',

    'sha256WithRSAEncryption',
    'ecdsa-with-SHA256',

    'sha384WithRSAEncryption',
    'ecdsa-with-SHA384',

    'sha512WithRSAEncryption',
    'ecdsa-with-SHA512',
);

my %HASHING_FUNCTION_STRENGTH_INDEX = map { $HASHING_FUNCTION_STRENGTH_ORDER[$_] => $_ } ( 0 .. $#HASHING_FUNCTION_STRENGTH_ORDER );

#There’s no OID “name” for extended validation,
#so we’ll report it using this faux name:
my $_CP_EV_NAME = '_cp_extended_validation';

my %X509_VALIDATION_STRENGTH_OID = (
    '2.23.140.1.2.1' => 'domain-validated',
    '2.23.140.1.2.2' => 'subject-identity-validated',
);

my %OID = (
    '1.3.6.1.5.5.7.1.1'  => 'authorityInfoAccess',
    '1.3.6.1.5.5.7.48.1' => 'OCSP',
    '1.3.6.1.5.5.7.48.2' => 'caIssuers',
    '1.3.6.1.5.5.7.3.1'  => 'serverAuth',
    '1.3.6.1.5.5.7.3.2'  => 'clientAuth',

    '1.2.840.10045.2.1' => Cpanel::Crypt::Constants::ALGORITHM_ECDSA,
    ( map { ( Cpanel::Crypt::ECDSA::Data::get_oid($_) => $_ ) } Cpanel::Crypt::ECDSA::Data::ACCEPTED_CURVES() ),
    '1.2.840.10045.4.3.1' => 'ecdsa-with-SHA224',
    '1.2.840.10045.4.3.2' => 'ecdsa-with-SHA256',
    '1.2.840.10045.4.3.3' => 'ecdsa-with-SHA384',
    '1.2.840.10045.4.3.4' => 'ecdsa-with-SHA512',

    '1.2.840.113549.1.1.1'  => Cpanel::Crypt::Constants::ALGORITHM_RSA,
    '1.2.840.113549.1.1.4'  => 'md5WithRSAEncryption',
    '1.2.840.113549.1.1.5'  => 'sha1WithRSAEncryption',
    '1.2.840.113549.1.1.11' => 'sha256WithRSAEncryption',
    '1.2.840.113549.1.1.12' => 'sha384WithRSAEncryption',
    '1.2.840.113549.1.1.13' => 'sha512WithRSAEncryption',
    '1.2.840.113549.1.1.14' => 'sha224WithRSAEncryption',
    '1.2.840.113549.1.9.1'  => 'emailAddress',
    '1.2.840.113549.1.9.14' => 'extensionRequest',
    '2.5.4.3'               => 'commonName',
    '2.5.4.5'               => 'serialNumber',
    '2.5.4.6'               => 'countryName',
    '2.5.4.7'               => 'localityName',
    '2.5.4.8'               => 'stateOrProvinceName',
    '2.5.4.9'               => 'streetAddress',
    '2.5.4.10'              => 'organizationName',
    '2.5.4.11'              => 'organizationalUnitName',
    '2.5.29.15'             => 'keyUsage',
    '2.5.29.37'             => 'extendedKeyUsage',
    '2.5.29.17'             => 'subjectAltName',
    '2.5.29.19'             => 'basicConstraints',

    # For APNs:
    '0.9.2342.19200300.100.1.1' => 'userId',

    #There is an obsolete variant of this OID, 2.5.29.3, that has
    #a different structure and doesn’t appear to be relevant to us.
    #OpenSSL doesn’t seem to like to parse the obsolete one any more
    #than we do; for example, pipe this into “openssl x509 -noout -text”:
    #https://bugs.wireshark.org/bugzilla/attachment.cgi?id=2191
    #
    #Just doing the modern OID should suffice for our needs.
    '2.5.29.32' => 'certificatePolicies',

    %X509_VALIDATION_STRENGTH_OID,
);

my %REVERSE_OID = reverse %OID;

my @keyUsage_fields = qw(
  digitalSignature
  contentCommitment
  keyEncipherment
  dataEncipherment
  keyAgreement
  keyCertSign
  cRLSign
  encipherOnly
  decipherOnly
);

my $locale;

sub compare_encryption_strengths ( $first, $second ) {
    my @strengths;

    my $i = 0;
    foreach my $item ( $first, $second ) {
        Cpanel::Crypt::Algorithm::dispatch_from_parse(
            $item,
            rsa => sub {
                $strengths[$i] = $_[0]{'modulus_length'};
            },
            ecdsa => sub {
                $strengths[$i] = Cpanel::Crypt::ECDSA::Data::get_equivalent_rsa_modulus_length( $_[0]{'ecdsa_curve_name'} ) or do {
                    die "Unrecognized ECDSA curve name: “$_[0]{'ecdsa_curve_name'}”";
                };
            },
        );
        ++$i;
    }

    return $strengths[0] <=> $strengths[1];
}

sub hashing_function_strength_comparison {
    my ( $a, $b ) = @_;

    # If we do not know the strength of the hashing function, we warn and assume 0
    return ( ( $HASHING_FUNCTION_STRENGTH_INDEX{$a} || ( warn("Unknown hash: “$a”") && 0 ) ) <=> ( $HASHING_FUNCTION_STRENGTH_INDEX{$b} || ( warn("Unknown hash: “$b”") && 0 ) ) );
}

#We can't always depend on the order of certs in CAB files.
#So, follow this logic to put them in order:
#   1) Make a subject-keyed hash of the certs, and a list of issuers.
#   2) The "leaf" cert is the one that isn't also an issuer.
#
#Returns
# boolean: status
# hashref: format
#   parsed:  The parsed certificate
#   text:    The certificate text (i.e., PEM format, not openssl's "-text")
#   subject_text: joined with \n
#   issuer_text:  joined with \n
sub find_leaf_in_cabundle {
    my $cab = shift or return;
    my $cab_object;
    require Cpanel::SSL::Objects::CABundle;
    eval { $cab_object = Cpanel::SSL::Objects::CABundle->new( 'cab' => $cab ); };
    if ($@) {
        return ( 0, $@ );
    }
    return $cab_object->find_leaf();
}

# This function reorders the certificates in a cabundle
# so the highest level (ones signed by the trusted root)
# come first
# This is what Apache wants
#
# Returns
# boolean: status
# text: a ASCII armored cabundle in the proper order
sub normalize_cabundle_order {
    my $cab = shift or return;
    my $cab_object;
    require Cpanel::SSL::Objects::CABundle;
    eval { $cab_object = Cpanel::SSL::Objects::CABundle->new( 'cab' => $cab ); };
    if ($@) {
        return ( 0, $@ );
    }
    return $cab_object->normalize_order_without_trusted_root_certs();
}

#Data portion is a hashref, keyed with the @RSA_ORDER values above.
#NOTE: Consider Crypt::RSA::Parse from CPAN in new code.
my $last_parsed_key;

sub parse_key_text {
    my $original_key = shift // return ( 0, 'No key given!' );

    Cpanel::Context::must_be_list();

    if ( $last_parsed_key && $last_parsed_key->[0] eq $original_key ) {
        return ( 1, $last_parsed_key->[1] );
    }

    if ( -1 != index( $original_key, 'BEGIN EC ' ) ) {
        return _parse_ecdsa($original_key);
    }

    my $old_rsa_format = index( $original_key, 'BEGIN RSA' ) > -1;

    my ( $ok, $key ) = get_key_from_text($original_key);
    return ( 0, $key ) if !$ok;

    $key = normalize($key);

    my $parsed;

    #RSA's special key file format
    #This is what "openssl genrsa" generates.
    if ($old_rsa_format) {
        ( $ok, $parsed ) = _parse_rsa_asn_base64($key);
        return ( 0, $parsed ) if !$ok;
    }

    #General PKCS private key file format--which we still expect to be RSA.
    #openssl genpkey generates keys in this format.
    else {
        ( $ok, my $asn ) = _parse_asn_base64($key);
        return ( 0, $asn ) if !$ok;

        my $format = eval { $asn->{'value'}[1]{'value'}[0]{'value'} };
        if ( !$format ) {
            _get_locale();
            return ( 0, $locale->maketext('The key text was not valid.') );
        }
        elsif ( $format eq $REVERSE_OID{ Cpanel::Crypt::Constants::ALGORITHM_RSA() } ) {
            ( $ok, $parsed ) = _parse_rsa_asn( ${ $asn->{'value'}[2]{'binary'} } );
            return ( 0, $parsed ) if !$ok;
        }
        elsif ( $format eq $REVERSE_OID{ Cpanel::Crypt::Constants::ALGORITHM_ECDSA() } ) {
            return _parse_ecdsa($original_key);
        }
        else {
            _get_locale();
            return ( 0, $locale->maketext( 'The “[_1]” key format is not valid.', $format ) );
        }
    }

    $last_parsed_key = [ $original_key, $parsed ];

    return ( 1, Cpanel::SSL::Parsed::Key->adopt($parsed) );
}

my $last_parsed_cert;

sub parse_certificate_text {
    my $original_text = shift // return ( 0, 'No certificate given!' );

    Cpanel::Context::must_be_list();

    if ( $last_parsed_cert && $last_parsed_cert->[0] eq $original_text ) {
        return ( 1, $last_parsed_cert->[1] );
    }

    my ( $ok, $text ) = get_certificate_from_text($original_text);
    return ( 0, $text ) if !$ok;

    my $parsed = [ _parse_x509_base64( normalize($text) ) ];

    if ( $parsed->[0] ) {
        $last_parsed_cert = [ $original_text, $parsed->[1] ];

        Cpanel::SSL::Parsed::Certificate->adopt( $parsed->[1] );
    }

    return @{$parsed};
}

sub parse_csr_text {
    my $text = shift // return ( 0, 'No CSR given!' );

    Cpanel::Context::must_be_list();

    ( my $ok, $text ) = get_csr_from_text($text);
    return ( 0, $text ) if !$ok;

    $text = normalize($text);
    return _parse_csr_base64($text);
}

sub validate_certificate_for_domain {
    my ( $cert, $domain ) = @_;
    my $msg;

    my ( $ok, $parse ) = parse_certificate_text($cert);
    return ( 0, $parse ) if !$ok;

    ( $ok, $msg ) = validate_allowed_domains( $parse->{'domains'} );
    return ( 0, $msg ) if !$ok;

    return ( 1, validate_domains_lists_have_match( $parse->{'domains'}, $domain ) );
}

sub validate_allowed_domains {
    my ($domains) = @_;

    # Avoid bad interactions with ACME TLS-SNI verification.
    my (@rejects) = grep { /\.invalid\.?$/ } @$domains;
    if (@rejects) {
        _get_locale();
        return ( 0, $locale->maketext( 'The following [numerate,_1,domain is,domains are] not allowed in a certificate because [numerate,_1,its top-level domain is,their top-level domains are] forbidden: [list_and_quoted,_2]', scalar @rejects, \@rejects ) );
    }
    return ( 1, 'OK' );
}

#
# validate_domains_match
# Given two lists of domains this function
# will check to see if any of them match and return 1
# if they do, and 0 if they do not.  This function understands wildcards
# and will permit matching a domain to a wildcard domain
# (ex.  dog.koston.org  == *.koston.org)
#
#TODO: Move this to Cpanel::WildcardDomain.
#
sub find_domains_lists_matches {
    return _find_domains_lists_matches( $_[0], $_[1] );
}

use constant _WC_PREFIX => '*.';

sub _find_domains_lists_matches {
    my ( $domains_list_1, $domains_list_2, $return_on_first_match ) = @_;

    if ( !$domains_list_1 || !$domains_list_2 ) {
        die Cpanel::Exception->create_raw("Need two domain lists!");
    }

    if ( defined $domains_list_1 && !ref $domains_list_1 ) { $domains_list_1 = [$domains_list_1]; }
    if ( defined $domains_list_2 && !ref $domains_list_2 ) { $domains_list_2 = [$domains_list_2]; }

    my $fewer_domains_ar;
    my %domains_hash_large;

    # This is an optimzation.  If they are the same size
    # its just fine.
    if ( scalar @{$domains_list_1} > scalar @{$domains_list_2} ) {
        @domains_hash_large{ map { tr/A-Z/a-z/r } @$domains_list_1 } = ();
        $fewer_domains_ar = $domains_list_2;
    }
    else {
        @domains_hash_large{ map { tr/A-Z/a-z/r } @$domains_list_2 } = ();
        $fewer_domains_ar = $domains_list_1;
    }

    #Case-insensitive matching. For now, just do ASCII.
    #TODO: implement Unicode case folding to match how DNS does it.
    #We copy the array to avoid mutating what was passed in.
    $fewer_domains_ar = [@$fewer_domains_ar];
    tr{A-Z}{a-z} for @$fewer_domains_ar;

    my %matches;

    my @wc_in_smaller;

    # Look for exact matches
    foreach my $domain (@$fewer_domains_ar) {
        push @wc_in_smaller, $domain if ( 0 == rindex( $domain, _WC_PREFIX(), 0 ) );

        if ( exists $domains_hash_large{$domain} ) {
            $matches{$domain} = undef;
            return [ keys %matches ] if $return_on_first_match;
        }
    }

    # Now handle wildcards that match non-wildcards.
    # NOTE: Wildcards matching wildcards are handled as exact matches.
    # We used to do this by iterating through all domains of both hashes,
    # but it’s more efficient (albeit more prolix) to iterate through just
    # the wildcards.

    for my $wc (@wc_in_smaller) {
        for my $non_wc ( keys %domains_hash_large ) {
            next if 0 == rindex( $non_wc, _WC_PREFIX(), 0 );

            next if !Cpanel::WildcardDomain::wildcard_domains_match( $wc, $non_wc );

            return [$non_wc] if $return_on_first_match;

            $matches{$non_wc} = undef;
        }
    }

    my @wc_in_larger = grep { 0 == rindex( $_, _WC_PREFIX(), 0 ) } keys %domains_hash_large;

    for my $wc (@wc_in_larger) {
        for my $non_wc (@$fewer_domains_ar) {
            next if 0 == rindex( $non_wc, _WC_PREFIX(), 0 );

            next if !Cpanel::WildcardDomain::wildcard_domains_match( $wc, $non_wc );

            return [$non_wc] if $return_on_first_match;

            $matches{$non_wc} = undef;
        }
    }

    return [ keys %matches ];
}

#TODO: Move this to Cpanel::WildcardDomain.
#
sub validate_domains_lists_have_match {
    return @{ _find_domains_lists_matches( @_, 1 ) } ? 1 : 0;
}

#This takes the domains on a vhost and domains on a cert and returns a hashref of:
#{
#   working_domains => [...], # Domains on the vhost that the cert covers
#   warning_domains => [...], # Domains on the vhost that the cert does NOT cover
#   extra_certificate_domains => [...],   # Domains NOT on the vhost that the cert covers
#
#NOTE: A wildcard cert technically covers an infinite number of domains.
#For these lists' purpose, though, we only consider a wildcard domain
#"unmatched"/"uncovered" if it didn't match anything in the install.
sub split_vhost_certificate_domain_lists {
    my ( $vhost_domains_ar, $cert_domains_ar ) = @_;

    my $working_domains_ar = find_domains_lists_matches( $vhost_domains_ar, $cert_domains_ar );

    my @warning_domains = do {
        my %vhd_lookup = map { $_ => 1 } @$vhost_domains_ar;
        delete @vhd_lookup{@$working_domains_ar};
        keys %vhd_lookup;
    };

    my @extra_certificate_domains = do {
        my %cd_lookup = map { $_ => 1 } @$cert_domains_ar;
        delete @cd_lookup{@$working_domains_ar};

        #Weed out wildcards from this last list that are actually matched with
        #a working domain.
        my @cert_wildcards = grep { tr{\*}{} } keys %cd_lookup;
        delete @cd_lookup{ grep { validate_domains_lists_have_match( [$_], $working_domains_ar ) } @cert_wildcards };

        keys %cd_lookup;
    };

    return {
        'working_domains'           => [ sort @$working_domains_ar ],
        'warning_domains'           => [ sort @warning_domains ],
        'extra_certificate_domains' => [ sort @extra_certificate_domains ],
    };
}

sub validate_cabundle_for_certificate {
    my ( $cab, $cert ) = @_;

    my ( $ok, $leaf ) = find_leaf_in_cabundle($cab);
    return ( 0, $leaf ) if !$ok;

    require Cpanel::SSL::Objects::Certificate;

    my $cert_obj;
    eval { $cert_obj = Cpanel::SSL::Objects::Certificate->new( 'cert' => $cert ) };
    return ( 0, $@ ) if $@;

    return ( 1, $leaf->subject_text() eq $cert_obj->issuer_text() ? 1 : 0 );
}

#----------------------------------------------------------------------
# Helper functions - public

sub hex_modulus_length {
    my $mod_hex = shift;
    substr( $mod_hex, 0, 1, '' ) while ( 0 == rindex( $mod_hex, "0", 0 ) );
    my $first = substr( $mod_hex, 0, 1, '' );

    return ( 4 * length $mod_hex ) + ( length sprintf( '%b', hex $first ) );
}

sub to_hex {
    return defined $_[0] ? unpack( 'H*', $_[0] ) : $_[0];
}

#A peculiarity of how ASN.1 stores integers whose top bit is set.
#e.g.: A modulus that begins b6d3fa will be encoded as 00b6d3fa...
#We need to strip off that leading 00, or else modulus length
#computations will be off.
#NB: A modulus will always begin and end with a 1 bit.
#
#Moreover, signatures are always stored with a leading 0.
#
#We serve both purposes, then, by just stripping null characters
#from the binary data before calling to_hex().
sub to_hex_number {
    my ($binary) = @_;
    return undef if !defined $binary;

    substr( $binary, 0, 1, '' ) while ( 0 == rindex( $binary, "\0", 0 ) );
    return unpack( 'H*', $binary );
}

#Implements parsing as described in RFC 2459, 4.1.2.5.1.
sub utctime_to_ts {
    my ($utctime) = @_;
    return if !defined $utctime;

    my ( $yr, $mo, $md, $h, $m, $s ) = (
        $utctime =~ m{
            \A
            ([0-9]*)    #year
            ([0-9]{2})  #month
            ([0-9]{2})  #mday
            ([0-9]{2})  #hour
            ([0-9]{2})  #minute
            ([0-9]{2})  #second
            Z\z
        }x
    );
    return undef if !defined $yr;

    if ( length $yr == 2 ) {
        $yr = ( ( $yr <= 50 ) ? 20 : 19 ) . $yr;
    }

    require Time::Local;
    return Time::Local::timegm_nocheck( $s, $m, $h, $md, $mo - 1, $yr );
}

# Some key files contain a certificate as well as a key, this will return just the key text
sub get_key_from_text {
    my ($text) = @_;

    my ( $ok, $pem ) = _get_pem_string( '(?:RSA\s|EC\s)?PRIVATE\sKEY', $text );
    return ( 1, $pem ) if $ok;

    _get_locale();
    return ( 0, $locale->maketext('The key text was not valid.') );
}

# Some certificate files contain a key as well as a certificate, this will return just the certificate text
sub get_certificate_from_text {
    my ($text) = @_;

    my ( $ok, $pem ) = _get_pem_string( 'CERTIFICATE', $text );
    return ( 1, $pem ) if $ok;

    _get_locale();
    return ( 0, $locale->maketext('The certificate text was not valid.') );
}

sub get_csr_from_text {
    my ($text) = @_;

    my ( $ok, $pem ) = _get_pem_string( 'CERTIFICATE\sREQUEST', $text );
    return ( 1, $pem ) if $ok;

    _get_locale();
    return ( 0, $locale->maketext('The certificate signing request text was not valid.') );
}

sub _get_pem_string {
    my ( $whatsit_re_part, $text ) = @_;

    if ( $text =~ /^[^-]*(-{1,5}BEGIN\s$whatsit_re_part-{1,5}[^-]*-{1,5}END\s$whatsit_re_part-{1,5})[^-]*$/ms ) {
        return ( 1, _ensure_pem_dashes("$1") );
    }

    return;
}

sub _ensure_pem_dashes {
    my ($pem) = @_;

    $pem =~ s[(?<!-)-{1,4}(?!-)][-----]g;

    return $pem;
}

sub demunge_ssldata {
    my ($ssldata) = @_;

    return if !length $ssldata;

    my $output = '';
    while ( $ssldata =~ m{-+BEGIN ([^-]+)-+\s+($_BASE64_CHAR_SPACES)\s*-+END[^\n]+-+}sog ) {
        my ( $whatsit, $base64 ) = ( $1, $2 );
        return if !$whatsit || !$base64;

        $base64 =~ tr{ \t\r\n\f}{}d;
        $base64 = join( "\n", ( $base64 =~ m{(.{1,64})}g ) );
        $base64 .= "\n" if substr( $base64, -1 ) ne "\n";

        $output .= "\n" if $output;
        $output .= "-----BEGIN $whatsit-----\n" . $base64 . "-----END $whatsit-----";
    }

    return $output;
}

#----------------------------------------------------------------------
# Helper functions - private

# returns the key/values we put into the parse hash
sub _parse_subject_key {
    my ($key_struct) = @_;

    my $key_type_oid = $key_struct->[0]{'value'}[0]{'value'};

    my $key_type_name = $OID{$key_type_oid};
    if ( !$key_type_name ) {
        return ( 0, "Unknown key type OID: “$key_type_oid”" );
    }

    my @key_parse = (
        key_algorithm => $key_type_name,
    );

    if ( $key_type_name eq Cpanel::Crypt::Constants::ALGORITHM_RSA ) {
        my $key = $key_struct->[1]{'value'};
        my ( $key_ok, $parsed_key ) = _parse_asn($key);
        return ( 0, $parsed_key ) if !$key_ok;    #This should never happen.

        my $modulus = ${ $parsed_key->{'value'}[0]{'binary'} };

        my $modulus_hex = to_hex_number($modulus);

        push @key_parse, (
            modulus         => $modulus_hex,
            modulus_length  => hex_modulus_length($modulus_hex),
            public_exponent => to_hex_number( ${ $parsed_key->{'value'}[1]{'binary'} } ),
        );
    }
    elsif ( $key_type_name eq Cpanel::Crypt::Constants::ALGORITHM_ECDSA ) {
        my $curve_oid  = $key_struct->[0]{'value'}[1]{'value'};
        my $curve_name = $OID{$curve_oid} or do {
            return ( 0, "Unsupported ECDSA curve OID: “$curve_oid”" );
        };

        my $ecdsa_public = ${ $key_struct->[1]{'binary'} };
        $ecdsa_public = to_hex_number($ecdsa_public);

        local ( $@, $! );
        require Cpanel::Crypt::ECDSA::Utils;

        push @key_parse, (
            ecdsa_curve_name => $curve_name,
            ecdsa_public     => Cpanel::Crypt::ECDSA::Utils::compress_public_point($ecdsa_public),
        );
    }
    else {
        return ( 0, "Cannot parse: $key_type_name" );
    }

    return ( 1, @key_parse );
}

sub _parse_csr_base64 {
    my $b64 = shift;

    my ( $ok, $decoded ) = _parse_asn_base64($b64);
    return ( 0, $decoded ) if !$ok;

    my $decoded_ar = $decoded->{'value'};
    my $body       = $decoded_ar->[0]{'value'};

    my ( $key_ok, @key_parts ) = _parse_subject_key( $body->[2]{'value'} );
    return ( 0, $key_parts[0] ) if !$key_ok;

    my $cdata = $decoded_ar->[0]{'value'};

    my $subject_ar = _parse_subject( $body->[1]{'value'} );
    my $subject_hr = { map { @$_ } @$subject_ar };

    my $exts = $cdata->[-1]{'value'}[0]{'value'};

    my @domains;
    my $cn = $subject_hr->{'commonName'};

    #NOTE: In addition to extensions, we could also grab challengePassword
    #and/or other attributes here.
    my $attrs = $body->[3] && $body->[3]{'value'};

    my $parsed_exts;

    if ($attrs) {
        for my $attr (@$attrs) {
            next if 'ARRAY' ne ref $attr->{'value'};

            my $type_oid = $attr->{'value'}[0]{'value'};
            next if !$type_oid || $type_oid ne $REVERSE_OID{'extensionRequest'};

            next if !$attr->{'value'}[1] || !$attr->{'value'}[1]{'value'} || !$attr->{'value'}[1]{'value'}[0] || !$attr->{'value'}[1]{'value'}[0]{'value'};
            my $exts = $attr->{'value'}[1]{'value'}[0]{'value'};
            next if !$exts;

            $parsed_exts = _parse_x509_extensions($exts);
            my $alt_names_ar = $parsed_exts->{'subjectAltName'} && $parsed_exts->{'subjectAltName'}{'value'} || [];
            @domains = (
                ( ( !length $cn || ( grep { $_ eq $cn } @$alt_names_ar ) ) ? () : $cn ),
                grep { !ref } @$alt_names_ar,
            );
        }
    }

    if ( !@domains ) {
        @domains = ( length $cn ? $cn : () );
    }

    my $signature_algorithm = $OID{ $decoded_ar->[1]{'value'}[0]{'value'} };

    return (
        1,
        Cpanel::SSL::Parsed::CSR->adopt(
            {
                %$subject_hr,
                subject_list        => $subject_ar,
                signature_algorithm => $signature_algorithm,
                signature           => to_hex_number( ${ $decoded_ar->[2]{'binary'} } ),
                extensions          => $parsed_exts,

                # i.e., the parts that depend on the key algorithm:
                @key_parts,

                #convenience
                domains => \@domains,
            }
        ),
    );
}

sub _determine_x509_validation_type {
    my ($parse) = @_;

    my $exts_hr = $parse->{'extensions'};
    if ($exts_hr) {
        my $pols_ar = $exts_hr->{'certificatePolicies'};
        $pols_ar &&= $pols_ar->{'value'};

        if ($pols_ar) {
            for my $pol_hr (@$pols_ar) {
                return 'dv' if $pol_hr->{'name'} eq 'domain-validated';
                return 'ov' if $pol_hr->{'name'} eq 'subject-identity-validated';
                return 'ev' if $pol_hr->{'name'} eq $_CP_EV_NAME;
            }
        }
    }

    return undef;
}

my @x509_ev_cache;

# TODO: Modularize the parsing, or offload to an external module.
sub _parse_x509_extensions {    ## no critic qw(ProhibitExcessComplexity)
    my ($extensions) = @_;

    my %extensions;

  EXTENSION:
    for my $ext (@$extensions) {
        next EXTENSION if $ext->{'identval'} != 0x30 || 'ARRAY' ne ref $ext->{'value'};    #ASN.1 sequences are 0x30.

        my $ext_seq = $ext->{'value'};

        my $oid = $ext_seq->[0] && $ext_seq->[0]{'value'};

        my $name = $oid && $OID{$oid};

        next EXTENSION if !$name;

        my $payload_node = $ext_seq->[-1];

        my ( $ext_ok, $ext_value );
        my $value_type = ord substr( ${ $payload_node->{'binary'} }, 0, 1 );
        ( $ext_ok, $ext_value ) = _parse_asn( ${ $payload_node->{'binary'} } );

        next EXTENSION if !$ext_ok || !$ext_value;

        if ( $name eq 'certificatePolicies' ) {
            next EXTENSION if 'ARRAY' ne ref $ext_value->{'value'};

            my $ret_ext_value;

            #We do NOT look for every single certificate policy. For now, we
            #look for policies whose value is a list with at least one value.
            #That first value should be either:
            #
            #   1) a value from %X509_VALIDATION_STRENGTH_OID
            #       This is very simple to check for.
            #
            #   2) a CA-specific extended validation OID
            #       Requires that we keep a separate list of OIDs
            #       that CAs use for extended validation.
            #       This seems to occur as the first in a two-value list,
            #       whose second value is the CA’s CPS.
            #
            for my $entry ( @{ $ext_value->{'value'} } ) {

                my $value = $entry->{'value'};

                my $policy_oid = $value && $value->[0];
                $policy_oid &&= $policy_oid->{'value'};

                my $policy_name = $policy_oid && $OID{$policy_oid};

                if ( !$policy_name ) {
                    if ( !@x509_ev_cache ) {
                        require Cpanel::JSON;
                        @x509_ev_cache = @{ Cpanel::JSON::LoadFile($EV_CACHE_FILE); };
                    }

                    for my $issuer_hr (@x509_ev_cache) {
                        next if $policy_oid ne $issuer_hr->{'oid'};
                        $policy_name = $_CP_EV_NAME;
                        last;
                    }
                }

                if ($policy_name) {
                    push @$ret_ext_value, {
                        name => $policy_name,
                    };
                }
            }

            $ext_value = $ret_ext_value;
        }
        elsif ( $name eq 'authorityInfoAccess' ) {
            next EXTENSION if 'ARRAY' ne ref $ext_value->{'value'};
            my $value;
            for my $entry ( @{ $ext_value->{'value'} } ) {
                $value = $entry->{'value'};
                if ( ref $value ) {
                    try {
                        my $oid   = $value->[0]{'value'};
                        my $value = $value->[1]{'value'};
                        if ( $oid && $OID{$oid} && $value && !( grep { ref } $oid, $value ) ) {
                            $extensions{ $OID{$oid} } = {
                                value => $value,
                            };
                        }
                    }
                    catch {
                        require Data::Dumper;
                        warn "Unparsable authorityInfoAccess entry in certificate:\n" . Data::Dumper::Dumper($value);
                    };
                }
            }
            next EXTENSION;
        }
        elsif ( $name eq 'subjectAltName' ) {
            next EXTENSION if 'ARRAY' ne ref $ext_value->{'value'};

            #Some SAN values are objects. There seems to be no value
            #for us to parse these since CAs always seem to duplicate
            #the object SAN values as plain values.
            my ( @san, $value );
            for my $entry ( @{ $ext_value->{'value'} } ) {
                $value = $entry->{'value'};
                if ( ref $value ) {
                    try {

                        #CA certificates can have “DirName” entries,
                        #which we don’t care about and which were mucking
                        #up our parsing. (See case CPANEL-2008.)
                        my $oid   = $value->[0]{'value'};
                        my $value = $value->[1]{'value'}[0]{'value'};
                        if ( $oid && $value && !( grep { ref } $oid, $value ) ) {
                            push @san, { oid => $oid, value => $value };
                        }
                    }
                    catch {
                        require Data::Dumper;
                        warn "Unparsable subjectAltName entry in certificate:\n" . Data::Dumper::Dumper($value);
                    };
                }
                else {
                    push @san, $value;
                }
            }

            $ext_value = \@san;
        }
        elsif ( $name eq 'basicConstraints' ) {
            $ext_value = {
                cA                => $ext_value->{'value'}[0]{'value'} ? 1 : 0,
                pathLenConstraint => $ext_value->{'value'}[1]{'value'},
              },
              ;
        }
        elsif ( $name eq 'extendedKeyUsage' ) {
            next EXTENSION if 'ARRAY' ne ref $ext_value->{'value'};

            my $ret_ext_value = {};

            for my $entry ( @{ $ext_value->{'value'} } ) {
                my $policy_oid  = $entry->{'value'};
                my $policy_name = $policy_oid && $OID{$policy_oid};
                if ($policy_name) {
                    $ret_ext_value->{$policy_name} = 1;
                }
            }

            $ext_value = $ret_ext_value;
        }
        elsif ( $name eq 'keyUsage' ) {
            my @bits = _parse_asn_bit_string( ${ $ext_value->{'binary'} } );

            my %flags;
            @flags{@keyUsage_fields} = @bits;
            delete @flags{ grep { !$flags{$_} } keys %flags };
            $ext_value = \%flags;
        }
        else {
            next EXTENSION;
        }

        my $is_critical;
        if ( scalar @$ext_seq > 2 ) {
            $is_critical = $ext_seq->[1]{'value'} ? 1 : 0;
        }

        $extensions{$name} = {
            critical => $is_critical ? 1 : 0,
            value    => $ext_value,
        };
    }

    return \%extensions;
}

sub _parse_x509_base64 {
    my $b64 = shift;

    my ( $ok, $decoded ) = _parse_asn_base64($b64);
    return ( 0, $decoded ) if !$ok;

    my $decoded_ar = $decoded->{'value'};

    if ( !ref $decoded_ar ) {
        _get_locale();
        return ( 0, $locale->maketext( 'An unknown error in “[_1]” occurred while parsing x509 data.', $decoded_ar ) );
    }

    my $cdata = $decoded_ar->[0]{'value'};

    if ( !ref $cdata ) {
        _get_locale();
        return ( 0, $locale->maketext( 'An unknown error in “[_1]” occurred while parsing x509 data.', $cdata ) );
    }

    #The code below will decrement these all by one if there is no version
    #in the certificate.
    my %cdata_order = (
        serial  => 1,
        issuer  => 3,
        dates   => 4,
        subject => 5,
        key     => 6,
    );

    #As it happens, some certificates, (e.g., in CAB files) are still
    #using the 1988 version of X.509, as indicated by the absence of a
    #version field.
    #
    #If the first $cdata component is a list container that has a single
    #integer inside it, that's the version; otherwise, we're at version 0.
    my $version     = 0;
    my $has_version = ( 'ARRAY' eq ref $cdata->[0]{'value'} ) && $cdata->[0]{'value'}[0] && defined $cdata->[0]{'value'}[0]{'value'};
    if ($has_version) {
        $version = $cdata->[0]{'value'}[0]{'value'};
    }
    else {
        for my $key ( keys %cdata_order ) {
            $cdata_order{$key}--;
        }
    }

    my $key_struct = $cdata->[ $cdata_order{'key'} ]{'value'};
    my ( $key_ok, @key_parse ) = _parse_subject_key($key_struct);
    return ( 0, $key_parse[0] ) if !$key_ok;

    my $issuer_ar = _parse_subject( $cdata->[ $cdata_order{'issuer'} ] );
    my $issuer_hr = { map { @$_ } @$issuer_ar };

    my $subject_ar = _parse_subject( $cdata->[ $cdata_order{'subject'} ] );
    my $subject_hr = { map { @$_ } @$subject_ar };

    my $exts = ( $version > 0 ) ? $cdata->[-1]{'value'}[0]{'value'} : undef;

    my $parsed_exts  = $exts && _parse_x509_extensions($exts);
    my $alt_names_ar = $exts && $parsed_exts->{'subjectAltName'} && $parsed_exts->{'subjectAltName'}{'value'} || [];

    #TODO: Would it be worthwhile to modify Encoding::BER
    #to return a "binary" property for each node?
    #We've already tweaked it to return this for primitive nodes.
    my $is_self_signed = join( "\n", map { @$_ } @$subject_ar ) eq join( "\n", map { @$_ } @$issuer_ar );

    my $subj_cn             = $subject_hr->{'commonName'};
    my $signature_algorithm = $OID{ $decoded_ar->[1]{'value'}[0]{'value'} };

    my $parse_hr = {

        #Certs store version as 0-indexed, but publicly they're 1-indexed.
        version             => 1 + $version,
        serial              => to_hex_number( ${ $cdata->[ $cdata_order{'serial'} ]{'binary'} } ),
        issuer              => $issuer_hr,
        issuer_list         => $issuer_ar,
        not_before          => scalar utctime_to_ts( $cdata->[ $cdata_order{'dates'} ]{'value'}[0]{'value'} ),
        not_after           => scalar utctime_to_ts( $cdata->[ $cdata_order{'dates'} ]{'value'}[1]{'value'} ),
        subject             => $subject_hr,
        subject_list        => $subject_ar,
        signature_algorithm => $signature_algorithm,
        signature           => to_hex_number( ${ $decoded_ar->[2]{'binary'} } ),
        extensions          => $parsed_exts,

        # i.e., the parts that depend on the key algorithm:
        @key_parse,

        #convenience
        is_self_signed => $is_self_signed ? 1 : 0,
        domains        => [
            ( !length $subj_cn || ( grep { $_ eq $subj_cn } @$alt_names_ar ) ? () : $subj_cn ),
            grep { !ref } @$alt_names_ar,    #ignore objects in subjectAltName
        ],
    };

    $parse_hr->{'validation_type'} = _determine_x509_validation_type($parse_hr);

    return ( 1, $parse_hr );
}

#Parses a base64-encoded ASN structure and returns the Encoding::BER result.
sub _parse_asn_base64 {
    my $b64 = shift;

    chomp $b64;

    if ( length($b64) % 4 ) {
        return ( 0, "Invalid base64: must be a multiple of 4 in length.\n" );
    }

    local $@;
    my $binary = eval {
        local $SIG{'__WARN__'} = sub { };
        local $SIG{'__DIE__'}  = sub { };

        return MIME::Base64::decode_base64($b64);
    };

    if ($@) {
        return ( 0, $@ );
    }
    elsif ( !$binary ) {    #just in case
        _get_locale();
        return ( 0, $locale->maketext( 'An unknown error in “[_1]” occurred. As a result of this error, the system could not parse this text: [_2]', 'decode_base64', $b64 ) );
    }

    return _parse_asn($binary);
}

sub _parse_asn_bit_string {
    my ($value) = @_;

    my ( $unused_bits, @bytes ) = unpack( 'C*', $value );

    my $ones_and_zeros = join q{}, map { sprintf( '%08b', $_ ) } @bytes;
    substr( $ones_and_zeros, 0 - $unused_bits, $unused_bits, q{} );

    return split m{}, $ones_and_zeros;
}

{
    my $_ber;
    my %_parse_asn_cache;

    #Parses an ASN object (tag, length, data) in binary form.
    #Previously this code only operated on SEQUENCEs, but then a need arose
    #to use it for BIT_STRINGs as well. It's probably best just to leave it
    #open-ended.
    sub _parse_asn {
        my $binary = shift or return;

        return ( 1, $_parse_asn_cache{$binary} ) if exists $_parse_asn_cache{$binary};

        require Cpanel::Encoding::BER;

        $_ber ||= Cpanel::Encoding::BER->new( 'warn' => sub { warn @_; } );

        local $@;

        #Otherwise, the $SIG{'__WARN__'} in Cpanel::Carp will spew ugliness.
        my ($struct) = eval {
            local $SIG{'__WARN__'} = sub { };
            local $SIG{'__DIE__'}  = sub { };
            $_ber->decode($binary);
        };

        if ($@) {
            my $err = $@;
            _get_locale();
            return ( 0, $locale->maketext( 'A critical error occurred while parsing the ASN.1 data: [_1]', $err ) );
        }
        elsif ( !$struct || !$struct->{'value'} ) {
            _get_locale();
            return ( 0, $locale->maketext('An unknown error occurred while parsing the ASN.1 data.') );
        }

        #Ensure that $binary is exactly as long as the ASN.1 structure expects.
        #It would be nice if Encoding::BER made this easier.
        my $second_byte = ord substr( $binary, 1, 1 );
        my $should_be_length;
        if ( $second_byte > 0x80 ) {
            my $size_octets = $second_byte - 0x80;
            $should_be_length = 2 + $size_octets + hex( unpack( 'H*', substr( $binary, 2, $size_octets ) ) );
        }
        else {
            $should_be_length = 2 + $second_byte;
        }

        if ( $should_be_length != length $binary ) {
            _get_locale();
            return ( 0, $locale->maketext( 'The ASN.1 data is corrupt. Its header indicates a length of [quant,_1,byte,bytes], but its content is [quant,_2,byte,bytes] long.', $should_be_length, length $binary ) );
        }

        if ( scalar keys %_parse_asn_cache > $MAX_OBJECTS_IN_CACHE ) {
            clear_cache();
        }

        return ( 1, $_parse_asn_cache{$binary} = $struct );
    }

    sub clear_cache {
        %_parse_asn_cache = ();
        return;
    }

}

#This parses an RSA key in binary form.
sub _parse_rsa_asn {
    my $binary = shift;

    my ( $ok, $decoded ) = _parse_asn($binary);
    return ( 0, $decoded ) if !$ok;

    return _parse_decoded_rsa_asn($decoded);
}

#This parses a base64-encoded RSA key.
sub _parse_rsa_asn_base64 {
    my $b64 = shift;

    my ( $ok, $decoded ) = _parse_asn_base64($b64);
    return ( 0, $decoded ) if !$ok;

    return _parse_decoded_rsa_asn($decoded);
}

#This parses the Encoding::BER structure into a hashref of:
#   { $oid_key1 => $val1, $oid_key2 => $val2, ... }
sub _parse_decoded_rsa_asn {
    my $decoded = shift;

    # Make a copy
    my $decoded_ar = [ @{ $decoded->{'value'} } ];

    #The first value in a private key is a useless 0 value.
    shift @$decoded_ar;
    return ( 0, 'No value provided in $decoded->{value} passed into _parse_decoded_rsa_asn' ) if !@$decoded_ar;

    my $parse = { map { $_ => to_hex_number( ${ ( shift @$decoded_ar )->{'binary'} } ) } @RSA_ORDER };
    $parse->{'modulus_length'} = hex_modulus_length( $parse->{'modulus'} );
    $parse->{'key_algorithm'}  = Cpanel::Crypt::Constants::ALGORITHM_RSA;

    return ( 1, $parse );
}

#Returns a arrayref of [ OID name => value ].
#This is the only safe way since sometimes certificates have more than one
#value for a given field (e.g., organizationalUnitName).
sub _parse_subject {
    my $subj_ar = shift;

    if ( 'HASH' eq ref $subj_ar ) {
        $subj_ar = $subj_ar->{'value'};
    }

    return [] if !$subj_ar;

    #Each object in the array is a 1-member ASN.1 SET;
    #that member is an ASN.1 SEQUENCE.
    #That SEQUENCE contains two values: the OID key, and the value.
    #NB: "openssl asn1parse -i" will illustrate this structure more clearly.
    return [
        map {
            my $seq     = $_->{'value'}[0]{'value'};
            my $oid_key = $seq->[0]{'value'};
            my $value   = $seq->[1]{'value'};

            if ( grep { 'bmp_string' eq $_ } @{ $seq->[1]{'type'} } ) {
                $value = Cpanel::Encoder::utf8::ucs2_to_utf8($value);
                Cpanel::Encoder::utf8::encode($value);
            }
            elsif ( grep { 'teletex_string' eq $_ } @{ $seq->[1]{'type'} } ) {
                $value = Cpanel::Encoder::utf8::teletex_to_utf8($value);
                Cpanel::Encoder::utf8::encode($value);
            }

            [ ( $OID{$oid_key} || $oid_key ) => $value ];
        } @{$subj_ar}
    ];
}

sub base64_to_pem {
    my ( $b64, $whatsit ) = @_;

    die "I need to know what this is! ($b64)" if !$whatsit;
    die "Should be all uppercase: “$whatsit”" if $whatsit =~ tr<A-Z><>c;

    return (
        "-----BEGIN $whatsit-----\n" . Cpanel::Base64::normalize_line_length($b64) . "-----END $whatsit-----",
    );
}

sub _parse_ecdsa ($key_pem) {

    local ( $@, $! );
    require Cpanel::Crypt::ECDSA;
    require Cpanel::Crypt::ECDSA::Utils;

    my $ecdsa = eval { Cpanel::Crypt::ECDSA->new( \$key_pem ) };
    return ( 0, $@ ) if !$ecdsa;

    my $hash = $ecdsa->key2hash();

    my $cname = $hash->{'curve_name'};
    $cname = Cpanel::Crypt::ECDSA::Data::get_canonical_name_or_die($cname);

    $hash->{'key_algorithm'}    = Cpanel::Crypt::Constants::ALGORITHM_ECDSA;
    $hash->{'ecdsa_curve_name'} = $cname;
    $hash->{'ecdsa_public'}     = Cpanel::Crypt::ECDSA::Utils::compress_public_point( $ecdsa->pub_hex() );

    return ( 1, Cpanel::SSL::Parsed::Key->adopt($hash) );
}

sub _get_locale {
    require Cpanel::Locale;
    return $locale ||= Cpanel::Locale->get_handle();
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::SSL::Utils - Utilities for use in the processing, parsing, or handling of SSL certificates, keys, CSRs, or CABs.

=head1 DESCRIPTION

This module includes general utility functions for use in the processing, parsing, or handling
of SSL certificates, keys, certificate signing requests (CSRs), or certificate authority bundles (CABs).

=head2 Methods

=over 4

=item C<find_leaf_in_cabundle>

The order of the certificates that make up a CAB is not guaranteed. So, this function will try to determine the leaf, or
last issuer, of a CAB and returns the leaf certificate in a Cpanel::SSL::Object::Certificate object.

=item C<normalize_cabundle_order>

This function reorders the certificates that make up a CAB so that the certificates closest to the top of the signing tree
will come first sequentially. Apache prefers well ordered CABs.

=item C<parse_key_text>

This function will parse the PEM key formatted text and return associated information.

=item C<parse_certificate_text>

This function will parse the PEM certificate formatted text and return associated information.

=item C<parse_csr_text>

This function will parse the PEM CSR formatted text and return associated information.

=item C<find_domains_lists_matches>

=item C<validate_domains_lists_have_match>

These functions accept two lists of domains and determine if the lists intersect. These functions understand wildcard domain matching rules
and will permit matching a domain to a wildcard domain I<(ex. dog.koston.org == *.koston.org)>.

=item C<validate_cabundle_for_certificate>

This function determines if the leaf of a PEM formatted CAB text matches the issuer on a PEM formatted certificate text.

=item C<hex_modulus_length>

This function accepts a modulus in hex format and returns the number of bits of that modulus.

=item C<to_hex>

This function accepts a binary value and returns that value in hexadecimal.

=item C<to_hex_number>

This function accepts a binary value, strips null characters from that binary value, then returns the value in hexadecimal.

=item C<utctime_to_ts>

This function accepts a UTC time and returns a corresponding time(2) value.

=item C<get_key_from_text>

This function will return a PEM formatted key text if it exists within a blob of passed in text.

=item C<get_certificate_from_text>

This function will return a PEM formatted certificate text if it exists within a blob of passed in text.

=item C<get_csr_from_text>

This function will return a PEM formatted CSR text if it exists within a blob of passed in text.

=back

=head1 SYNOPSYS

 use Cpanel::SSL::Utils ();

 my ( $ok, $leaf_certificate ) = Cpanel::SSL::Utils::find_leaf_in_cabundle( $cabundle_full_text );
 if ($ok) {
     $leaf_certificate->isa('Cpanel::SSL::Object::Certificate');
 }
 else {
     print "Error $leaf_certificate\n";
 }

 ( $ok, my $ordered_cabundle_text ) = Cpanel::SSL::Utils::normalize_cabundle_order( $cabundle_full_text );

 # The parse methods fit the same form
 ( $ok, my $parsed_key_hash ) = Cpanel::SSL::Utils::parse_key_text( $key_full_text );

 ( $ok, my $parsed_certificate_hash ) = Cpanel::SSL::Utils::parse_certificate_text( $certificate_full_text );

 ( $ok, my $parsed_csr_hash ) = Cpanel::SSL::Utils::parse_csr_hash( $csr_full_text );

 ( $ok, my $domain_matches_certificate ) = Cpanel::SSL::Utils::validate_certificate_for_domain( $full_certificate_text,
                                                                                                $domain_to_match );

 die "Unable to parse certificate $domain_matches_certificate" if !$ok;

 $domain_matches_certificate ? print "Matches\n" : print "Doesn't match\n";

 my @list_intersection = Cpanel::SSL::Utils::find_domains_lists_matches( qw( www.aardvark.tld vark.tld ants.tld ),
                                                                         qw( *.aardvark.tld ants.tld ) );

 my $lists_intersect = Cpanel::SSL::Utils::validate_domains_lists_have_match( qw( www.aardvark.tld vark.tld ants.tld ),
                                                                              qw( *.aardvark.tld ants.tld ) );

 $lists_intersect ? print "Intersection detected.\n" : "No matches found.\n";

 ( $ok, my $cabundle_matches_certificate ) = Cpanel::SSL::Utils::validate_cabundle_for_certificate( $cabundle_full_text,
                                                                                                    $certificate_full_text );

 my $modulus_length = Cpanel::SSL::Utils::hex_modulus_length( $hex_modulus_text );

 my $hex_value = Cpanel::SSL::Utils::to_hex( $binary_value );

 my $hex_number = Cpanel::SSL::Utils::to_hex_number( $binary_value );

 my $ticks_since_epoc = Cpanel::SSL::Utils::utctime_to_ts( $utc_time );

 my $key_text = Cpanel::SSL::Utils::get_key_from_text( $certificate_key_and_csr_full_text );

 my $certificate_text = Cpanel::SSL::Utils::get_certificate_from_text( $certificate_key_and_csr_full_text );

 my $csr_text = Cpanel::SSL::Utils::get_csr_from_text( $certificate_key_and_csr_full_text );

 my $split_domains_hr = Cpanel::SSL::Utils::split_vhost_certificate_domain_lists( $vh_domains_ar, $cert_domains_ar );

=cut
