package Cpanel::OpenSSL;

# cpanel - Cpanel/OpenSSL.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use parent 'Cpanel::OpenSSL::Base';

use Cpanel::Chdir            ();
use Cpanel::Crypt::Algorithm ();
use Cpanel::FileUtils::Write ();
use Cpanel::LoadFile         ();
use Cpanel::Logger           ();
use Cpanel::PwCache          ();
use Cpanel::RSA              ();
use Cpanel::StringFunc::Case ();
use Cpanel::OpenSSL::Base    ();
use Cpanel::SSL::Constants   ();

our $DEFAULT_KEY_SIZE;
*DEFAULT_KEY_SIZE = \$Cpanel::RSA::DEFAULT_KEY_SIZE;

my %SUBJECT_COMPONENTS = map { $_ => undef } qw(
  countryName
  emailAddress
  localityName
  organizationName
  organizationalUnitName
  stateOrProvinceName
);

my $OPENSSL_CONFIG_TEMPLATE = <<END;
[ req ]
prompt = no
default_bits = $DEFAULT_KEY_SIZE
default_md = sha256
distinguished_name = req_distinguished_name
attributes = req_attributes
x509_extensions = v3_ca
req_extensions = v3_req
string_mask = utf8only

[ req_distinguished_name ]
<<distinguished_name>>

[ req_attributes ]
challengePassword=<<csr_password>>

[ v3_req ]
subjectAltName = \@alt_names

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = CA:false
authorityKeyIdentifier  = keyid:always, issuer:always
extendedKeyUsage        = serverAuth, clientAuth
subjectAltName = \@alt_names

[ alt_names ]
<<dns_list>>
END

my $logger = Cpanel::Logger->new();

my $is_positive_integer = sub {
    my ($n) = @_;
    return defined $n && $n =~ /^[+]?[0-9]+$/ && $n > 1;
};

my $DEFAULT_CERTIFICATE_VALIDITY_IN_DAYS = 365;

sub _get_default_output_hash {
    my %output = ( 'status' => 0, 'message' => '', 'stdout' => '', 'stderr' => '', );
    return wantarray ? %output : \%output;
}

#----------------------------------------------------------------------
# The “workhorse” method of this class.
# Accepts key/value pairs:
#
#   args - required, an arrayref of arguments (the first being the command)
#   stdin - optional, a string to pass in
#
# Returns a hashref of:
#
#   CHILD_ERROR (i.e., $?)
#   message
#   stdout
#   stderr
#   status - XXX DO NOT USE THIS!!! It is ALWAYS set to 1! XXX
#
sub run {
    my ( $self, %OPTS ) = @_;

    local ( $@, $! );

    require Cwd;
    my $basepath = Cwd::fastcwd();
    my ( $user, $homedir ) = ( Cpanel::PwCache::getpwuid($>) )[ 0, 7 ];
    local $ENV{'HOME'} = $homedir;
    local $ENV{'USER'} = $user;

    my $chdir = Cpanel::Chdir->new('/');    # ensure openssl never writes to cwd

    my $output = _get_default_output_hash();

    require Cpanel::SafeRun::Object;
    my $run = eval {
        Cpanel::SafeRun::Object->new(
            'program' => $self->{'sslbin'},
            'args'    => $OPTS{'args'},

            $OPTS{'stdin'} ? ( 'stdin' => $OPTS{'stdin'} ) : (),
        );
    };
    if ( !$run ) {
        my $err = $@;
        $output->{'message'} = "Failed to execute $self->{'sslbin'}: $err";
        $logger->warn( $output->{'message'} );
        $output->{'stderr'} = $err;

        # Do not set 'stdout' as its presence (or lack of) is used to show that openssl execution failed
        delete $output->{'stdout'};    # shouldn't exist

        return $output;
    }

    $output->{'stdout'}      = $run->stdout();
    $output->{'stderr'}      = $run->stderr();
    $output->{'CHILD_ERROR'} = $run->CHILD_ERROR();

    #TODO: “status” should become (!$? ? 1 : 0) in 11.58.
    $output->{'status'} = 1;

    $output->{'message'} = 'Executed ' . $self->{'sslbin'} . ' ' . join( ' ', @{ $OPTS{'args'} } );
    return $output;
}

sub generate_key {
    my ( $self, $args_ref ) = @_;

    $args_ref ||= {};

    my $keyfile = $args_ref->{'keyfile'};

    if ( length $keyfile && -e $keyfile ) {
        unlink $keyfile;    # Existence of an old key file will cause additional prompting
    }

    if ( !$args_ref->{'keysize'} ) {
        $args_ref->{'keysize'} = $DEFAULT_KEY_SIZE;
    }

    if ( $args_ref->{'keysize'} < $DEFAULT_KEY_SIZE ) {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();

        my $ret = { status => 0, message => $locale->maketext( '[numf,_1]-bit encryption is too weak to provide adequate security. This system will only generate keys with at least [numf,_2]-bit encryption.', $args_ref->{'keysize'}, $DEFAULT_KEY_SIZE ) };

        #Some callers expect this.
        $ret->{'stderr'} = $ret->{'message'};

        return $ret;
    }

    require Crypt::OpenSSL::RSA;

    my $rsa = 'Crypt::OpenSSL::RSA'->generate_key( $args_ref->{'keysize'} );

    my $output = {
        'status' => $rsa ? 1 : 0,
        'stdout' => $rsa->get_private_key_string()
    };

    if ( length $keyfile ) {
        Cpanel::FileUtils::Write::overwrite( $keyfile, $output->{'stdout'}, 0600 );
    }

    return $output;
}

sub _resolve_digest {
    my ($digest) = @_;
    my $default = 'sha256';

    # Case 118297: Google, among others, wants to kill MD5 and SHA1
    # SSL Certificates. Since some CAs (notably StartSSL) auto-generate
    # Certificates using the same algorithm as in the CSR, we want
    # to only allow SHA256 and better
    if ( !defined $digest || $digest !~ m/^(?:sha256|sha384|sha512)$/i ) {
        return $default;
    }

    return Cpanel::StringFunc::Case::ToLower($digest);
}

#Takes the arguments to generate_cert and generate_csr and
#generates a custom openssl.cnf from them.
#
#NOTE: This function can throw exceptions because this is a pretty deep layer;
#something earlier should have validated the input.
sub _generate_openssl_config {
    my %conf = @_;

    my @domains;
    if ( $conf{'domains'} ) {
        @domains = @{ $conf{'domains'} };
    }
    else {
        @domains = ref $conf{'hostname'} ? @{ $conf{'hostname'} } : ( $conf{'hostname'} );
    }

    die 'Empty domain list!' if !@domains;

    tr{A-Z}{a-z} for @domains;    #lower-case

    #uniq()-ify
    my %dupe_domains;
    @domains = grep { !$dupe_domains{$_}++ } @domains;

    $conf{'hostname'} = $domains[0];

    die "Invalid domains list: @domains\n" if grep { tr{\r\n}{} } @domains;

    my $conf_text = $OPENSSL_CONFIG_TEMPLATE;

    # We used to avoid the subjectAltName extension when there is only one
    # name on the certificate, but macOS Catalina now expects every cert to
    # have a subjectAltName extension, so we now publish subjectAltName on
    # everything.
    {
        my $count    = 0;
        my $dns_list = join(
            q{},
            ( map { $count++; "DNS.$count = $_\n"; } @domains )
        );
        $conf_text =~ s{<<dns_list>>}{$dns_list};
    }

    my %subj = map { length $conf{$_} ? ( $_ => $conf{$_} ) : () } keys %SUBJECT_COMPONENTS;

    #Quote these since, as far as this module goes, they can be anything.
    s{([\\"])}{\\$1}g for values %subj;
    $_ = qq{"$_"} for values %subj;

    if ( length $domains[0] <= Cpanel::SSL::Constants::MAX_CN_LENGTH() ) {
        $subj{'commonName'} = $domains[0];
    }

    # There has to be *something* in the subject field.
    if ( !%subj ) {
        $subj{'countryName'} = 'XX';
    }

    my $subject_text = join( q{}, map { "$_=$subj{$_}\n" } keys %subj );

    $conf_text =~ s{<<distinguished_name>>}{$subject_text};

    if ( length $conf{'password'} ) {
        die "Invalid CSR password: $conf{'password'}\n" if $conf{'password'} =~ tr{\r\n}{};
        $conf_text =~ s{<<csr_password>>}{$conf{'password'}};
    }
    else {
        $conf_text =~ s{(challengePassword)}{#$1};
    }

    return $conf_text;
}

sub _verify_key_path_encryption_strength {
    my ($key_path) = @_;

    open( my $key_fh, '<', $key_path ) or do {
        my ($err) = $!;

        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();

        return ( 0, $locale->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $key_path, $err ) );
    };
    my $key_text = do { local $/; <$key_fh> };
    close $key_fh;

    $key_text =~ s{\A\s+|\s+\z}{}g;

    require Cpanel::SSL::Utils;
    my ( $key_ok, $key_parse ) = Cpanel::SSL::Utils::parse_key_text($key_text);
    return ( 0, $key_parse ) if !$key_ok;

    my $err;

    Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $key_parse,
        rsa => sub {
            if ( $key_parse->{'modulus_length'} < $DEFAULT_KEY_SIZE ) {
                require Cpanel::Locale;
                my $locale = Cpanel::Locale->get_handle();

                $err = $locale->maketext( 'This key uses [numf,_1]-bit [asis,RSA] encryption, which is too weak to provide adequate security. Use an [asis,ECDSA] key, or use an [asis,RSA] key with at least [numf,_2]-bit encryption.', $key_parse->{'modulus_length'}, $DEFAULT_KEY_SIZE );
            }
        },
        ecdsa => sub {
            require Cpanel::Crypt::ECDSA::Data;
            if ( !Cpanel::Crypt::ECDSA::Data::curve_name_is_valid( $key_parse->{'ecdsa_curve_name'} ) ) {
                $err = "Unknown or inadequate ECDSA curve: “$key_parse->{'ecdsa_curve_name'}”";
            }
        },
    );

    return ( 0, $err ) if $err;

    return 1;
}

sub generate_cert {
    my ( $self, $args_ref ) = @_;

    if ( !$args_ref->{'keyfile'} || ( !$args_ref->{'hostname'} && !$args_ref->{'domains'} ) ) {
        return { 'status' => 0, 'message' => 'Invalid arguments', };
    }

    my ( $modulus_ok, $modulus_msg ) = _verify_key_path_encryption_strength( $args_ref->{'keyfile'} );
    if ( !$modulus_ok ) {
        return { status => 0, message => $modulus_msg };
    }

    if ( !defined $args_ref->{'days'} || !$args_ref->{'days'} || !$is_positive_integer->( $args_ref->{'days'} ) ) {
        $args_ref->{'days'} = $DEFAULT_CERTIFICATE_VALIDITY_IN_DAYS;
    }

    my $outfile = $args_ref->{'crtfile'};

    if ( length $outfile && -e $outfile ) {
        unlink $outfile;    # Existence of an old cert file will cause additional prompting
    }

    my $digest = '-' . _resolve_digest( $args_ref->{'digest'} );

    local $@;
    my $conf = eval { _generate_openssl_config(%$args_ref) };
    if ($@) {
        return { status => 0, stderr => $@ };
    }

    my $output = $self->run(
        'args' => [
            'req',
            '-new',
            '-x509',
            '-utf8',
            '-days'       => $args_ref->{'days'},
            '-set_serial' => int( rand(9999999999) ),
            $digest,
            '-key'    => $args_ref->{'keyfile'},
            '-config' => '/dev/stdin',
            ( $outfile ? ( '-out' => $outfile ) : () ),
        ],
        'stdin' => $conf,
    );

    if ($outfile) {
        $output->{'status'} = -e $outfile ? 1 : 0;
    }
    else {
        $output->{'status'} = $output->{'stdout'} ? 1 : 0;
    }

    return $output;
}

#XXX: Consider using Cpanel::SSL::Create::csr() instead.
sub generate_csr {
    my ( $self, $args_ref ) = @_;

    if ( !$args_ref->{'keyfile'} || ( !$args_ref->{'hostname'} && !$args_ref->{'domains'} ) ) {
        return { 'status' => 0, 'message' => 'Invalid arguments', };
    }

    my ( $modulus_ok, $modulus_msg ) = _verify_key_path_encryption_strength( $args_ref->{'keyfile'} );
    if ( !$modulus_ok ) {
        return { status => 0, message => $modulus_msg };
    }

    my $csrfile = $args_ref->{'csrfile'};

    if ( $csrfile && -e $csrfile ) {
        unlink $csrfile;    # Existence of an old csr file will cause additional prompting
    }

    local $@;
    my $conf = eval { _generate_openssl_config(%$args_ref) };
    if ($@) {
        return { status => 0, stderr => $@ };
    }

    my $digest = '-' . _resolve_digest( $args_ref->{'digest'} );

    my $output = $self->run(
        'args' => [
            'req',
            '-new',
            $digest,
            '-utf8',
            '-key'    => $args_ref->{'keyfile'},
            '-config' => '/dev/stdin',
            ( $csrfile ? ( '-out' => $csrfile ) : () ),
        ],

        'stdin' => $conf,
    );

    if ($csrfile) {
        if ( -e $csrfile ) {
            $output->{'status'} = 1;
        }

        # Work around for 0.9.8h problems: http://cvs.openssl.org/chngview?cn=17196
        # we need the version to check for the issue during CSR requests
        else {
            $output->{'status'} = 0;

            if ( !$self->{'version'} ) {
                my $version_output = $self->run( 'args' => ['version'], );
                chomp $version_output->{'stdout'};
                if ( $version_output->{'stdout'} =~ m/^openssl\s+(\S+)\s+/i ) {
                    $self->{'version'} = $1;
                }
                else {
                    $self->{'version'} = $version_output->{'stdout'};
                }
            }

            if ( $self->{'version'} eq '0.9.8h' ) {
                $logger->info('Attempting workaround for failed CSR generation (Bug in OpenSSL 0.9.8h).');
                my $orig_ssl_bin = $self->{'sslbin'};
                while ( $self->{'version'} eq '0.9.8h' ) {
                    $self->{'sslbin'} = Cpanel::OpenSSL::Base::find_ssl(1);
                    last if !$self->{'sslbin'};
                    $logger->info("Testing alternate $self->{'sslbin'}");
                    my $version_output = $self->run( 'args' => ['version'], );
                    chomp $version_output->{'stdout'};
                    if ( $version_output->{'stdout'} =~ m/^openssl\s+(\S+)\s+/i ) {
                        $self->{'version'} = $1;
                    }
                    else {
                        $self->{'version'} = $version_output->{'stdout'};
                    }
                }

                if ( $self->{'sslbin'} && $self->{'version'} ne '0.9.8h' ) {
                    $logger->info("Generating CSR from alternate $self->{'sslbin'}");
                    my $alt_output = $self->generate_csr($args_ref);
                    $self->{'sslbin'} = $orig_ssl_bin;    # Reset

                    if ( -e $args_ref->{'csrfile'} ) {
                        $alt_output->{'status'} = 1;
                    }
                    else {
                        $output->{'message'}    = "Failed to generate CSR using $self->{'sslbin'}";
                        $alt_output->{'status'} = 0;
                    }
                    return $alt_output;
                }
            }
            else {
                $logger->warn("Failed to generate CSR using OpenSSL $self->{'version'}");
            }
        }
    }
    else {
        $output->{'status'} = $output->{'stdout'} ? 1 : 0;
    }

    return $output;
}

sub generate_public_key {
    my ( $self, $args_ref ) = @_;

    if ( !$args_ref->{'keyfile'} || !$args_ref->{'pubkeyfile'} ) {
        return { 'status' => 0, 'message' => 'Invalid arguments', };
    }
    elsif ( !-e $args_ref->{'keyfile'} ) {
        return { 'status' => 0, 'message' => 'Missing key file', };
    }

    require Crypt::OpenSSL::RSA;

    my $key_text = Cpanel::LoadFile::load( $args_ref->{'keyfile'} );
    if ( !$key_text ) {
        return { 'status' => 0, 'message' => 'The keyfile is empty.' };
    }

    my $rsa    = 'Crypt::OpenSSL::RSA'->new_private_key($key_text);
    my $public = $rsa->get_public_key_x509_string();

    Cpanel::FileUtils::Write::overwrite( $args_ref->{'pubkeyfile'}, $public, 0600 );
    return {
        'status' => 1,
    };
}

sub generate_public_key_from_private_key {
    my ( $self, $args_ref ) = @_;

    if ( !$args_ref->{'key'} ) {
        return { 'status' => 0, 'message' => 'Invalid arguments: missing “key”', };
    }

    require Crypt::OpenSSL::RSA;

    my $rsa = 'Crypt::OpenSSL::RSA'->new_private_key( $args_ref->{'key'} ) or return {
        'status'  => 0,
        'message' => "Failed to load RSA key"
    };

    return {
        'stdout' => $rsa->get_public_key_x509_string(),
        'status' => 1,
    };
}

sub get_key_text {
    my ( $self, $args_ref ) = @_;

    my $output;
    if ( !$args_ref->{'keyfile'} && !$args_ref->{'stdin'} ) {
        return { 'status' => 0, 'message' => 'Invalid arguments', };
    }
    elsif ( $args_ref->{'keyfile'} ) {
        if ( !-e $args_ref->{'keyfile'} ) {
            return { 'status' => 0, 'message' => 'Missing key file', };
        }
        $output = $self->run( 'args' => [ 'pkey', '-noout', '-text', '-in', $args_ref->{'keyfile'} ] );
        if ( $output->{'stdout'} ) {
            $output->{'status'} = 1;
            $output->{'text'}   = $output->{'stdout'};
            return $output;
        }
    }
    elsif ( $args_ref->{'stdin'} ) {
        $output = $self->run( 'stdin' => $args_ref->{'stdin'}, 'args' => [ 'pkey', '-noout', '-text' ] );
        if ( $output->{'stdout'} ) {
            $output->{'status'} = 1;
            $output->{'text'}   = $output->{'stdout'};
            return $output;
        }
    }
    $output->{'status'}  = 0;
    $output->{'message'} = 'Unknown Error';
    return $output;
}
*parse_key = \&get_key_text;

sub get_cert_text {
    my ( $self, $args_ref ) = @_;

    my $output;
    if ( !$args_ref->{'crtfile'} && !$args_ref->{'stdin'} ) {
        return { 'status' => 0, 'message' => 'Invalid arguments', };
    }
    elsif ( $args_ref->{'crtfile'} ) {
        if ( !-e $args_ref->{'crtfile'} ) {
            return { 'status' => 0, 'message' => 'Missing certificate file', };
        }
        $output = $self->run( 'args' => [ 'x509', '-noout', '-text', '-nameopt' => 'oneline,-esc_msb', '-in', $args_ref->{'crtfile'}, ] );
        if ( $output->{'stdout'} ) {
            $output->{'status'} = 1;
            $output->{'text'}   = $output->{'stdout'};
            return $output;
        }
    }
    elsif ( $args_ref->{'stdin'} ) {
        $output = $self->run( 'stdin' => $args_ref->{'stdin'}, 'args' => [ 'x509', '-noout', '-text', '-nameopt' => 'oneline,-esc_msb' ] );
        if ( $output->{'stdout'} ) {
            $output->{'status'} = 1;
            $output->{'text'}   = $output->{'stdout'};
            return $output;
        }
    }
    $output->{'status'}  = 0;
    $output->{'message'} = 'Unknown Error';
    return $output;
}
*parse_certificate = \&get_cert_text;

sub _get_cert_hash {
    my ( $self, $args_ref ) = @_;

    my @cmd_args = ( 'x509', '-noout', $args_ref->{'hash_arg'} );
    my @run_args = ( 'args' => \@cmd_args );

    if ( $args_ref->{'crtfile'} ) {
        if ( !-f $args_ref->{'crtfile'} ) {
            return { 'status' => 0, 'message' => 'Missing certificate file', };
        }
        push @cmd_args, '-in', $args_ref->{'crtfile'};
    }
    elsif ( $args_ref->{'stdin'} ) {
        push @run_args, 'stdin' => $args_ref->{'stdin'};
    }
    else {
        return { 'status' => 0, 'message' => 'Invalid arguments', };
    }

    my $output = $self->run(@run_args);

    return $output;
}

sub get_cert_subject_hash {
    my ( $self, $args_hr ) = @_;

    return $self->_get_cert_hash( { %$args_hr, 'hash_arg' => '-subject_hash' } );
}

sub get_csr_text {
    my ( $self, $args_ref ) = @_;

    my $output;
    if ( !$args_ref->{'csrfile'} && !$args_ref->{'stdin'} ) {
        return { 'status' => 0, 'message' => 'Invalid arguments', };
    }
    elsif ( $args_ref->{'csrfile'} ) {
        if ( !-e $args_ref->{'csrfile'} ) {
            return { 'status' => 0, 'message' => 'Missing certificate signing request file', };
        }
        $output = $self->run( 'args' => [ 'req', '-noout', '-text', '-nameopt' => 'oneline,-esc_msb', '-in', $args_ref->{'csrfile'}, ] );
        if ( $output->{'stdout'} ) {
            $output->{'status'} = 1;
            $output->{'text'}   = $output->{'stdout'};
            return $output;
        }
    }
    elsif ( $args_ref->{'stdin'} ) {
        $output = $self->run( 'stdin' => $args_ref->{'stdin'}, 'args' => [ 'req', '-noout', '-text', '-nameopt' => 'oneline,-esc_msb' ] );
        if ( $output->{'stdout'} ) {
            $output->{'status'} = 1;
            $output->{'text'}   = $output->{'stdout'};
            return $output;
        }
    }
    $output->{'status'}  = 0;
    $output->{'message'} = 'Unknown Error';
    return $output;
}
*parse_csr = \&get_csr_text;

#DEPRECATED. Use Cpanel::SSL::Utils::parse_key_text() instead.
sub get_key_modulus {
    my ( $self, $args_ref ) = @_;

    my $output;
    if ( !$args_ref->{'keyfile'} && !$args_ref->{'stdin'} ) {
        return { 'status' => 0, 'message' => 'Invalid arguments', };
    }
    elsif ( $args_ref->{'keyfile'} ) {
        if ( !-e $args_ref->{'keyfile'} ) {
            return { 'status' => 0, 'message' => 'Missing key file', };
        }
        $output = $self->run( 'args' => [ 'rsa', '-noout', '-modulus', '-in', $args_ref->{'keyfile'} ] );
        if ( $output->{'stdout'} ) {
            $output->{'status'}  = 1;
            $output->{'modulus'} = $output->{'stdout'};
            chomp $output->{'modulus'};
            return $output;
        }
    }
    elsif ( $args_ref->{'stdin'} ) {
        $output = $self->run( 'stdin' => $args_ref->{'stdin'}, 'args' => [ 'rsa', '-noout', '-modulus' ] );
        if ( $output->{'stdout'} ) {
            $output->{'status'}  = 1;
            $output->{'modulus'} = $output->{'stdout'};
            chomp $output->{'modulus'};
            return $output;
        }
    }
    $output->{'status'}  = 0;
    $output->{'message'} = 'Unknown Error';
    return $output;
}

sub get_key_size {
    my ( $self, %args ) = @_;

    return unless $args{keyfile} && -e $args{keyfile};

    open( my $key_fh, '<', $args{keyfile} ) or do {
        require Cpanel::Locale;
        my $locale = Cpanel::Locale->get_handle();

        $logger->warn( $locale->maketext( 'The system failed to open the file “[_1]” because of an error: [_2]', $args{keyfile}, $! ) );
        return;
    };
    my $key_text = do { local $/; <$key_fh> };
    close $key_fh;

    $key_text =~ s{\A\s+|\s+\z}{}g;

    require Cpanel::SSL::Utils;
    my ( $key_ok, $key_parse ) = Cpanel::SSL::Utils::parse_key_text($key_text);

    if ( !$key_ok ) {
        $logger->warn($key_parse);
        return;
    }

    return $key_parse->{'modulus_length'};
}

sub verify_cipher_string {
    my ( $self, $string ) = @_;

    # might as well short circuit the openssl call if we know its junk
    return if !$string;
    return if $string =~ m{\s};

    # The EA4 apache stack is built against our own openssl (ea-openssl),
    # but the perl SSLeay modules are built against the distro-provided openssl,
    # so there *could* be a discrepency with this check if the supported ciphers
    # ever diverge.
    #
    # But, this check previously relied on the distro-provided openssl, so we
    # are not introducing any *new* avenue for these discrepencies.
    my $ctx = eval {

        # Need to initialize the SSL library here to avoid 'library has no ciphers' errors.
        # This is needed because we perform this check in a fork+exec of the whostmgr2 binary,
        # that does not benefit from the Net::SSLeay::initialize() call in cpsrvd.
        require Cpanel::NetSSLeay::CTX;
        Net::SSLeay::SSLeay_add_ssl_algorithms();
        Cpanel::NetSSLeay::CTX->new();
    };

    if ( !$ctx ) {
        $logger->warn("The system failed to determine the validity of the OpenSSL cipher list, '$string', because of the following error: $@");
        return;
    }

    # A failure here doesn’t necessarily mean the string is invalid because
    # OpenSSL could have had its own internal failure prior to completing
    # the validity check. This is probably close enough:
    eval { $ctx->set_cipher_list($string); 1 };
    if ($@) {
        $logger->warn("OpenSSL rejected “$string” as a cipher list: $@");
        return;
    }

    return 1;
}

1;
