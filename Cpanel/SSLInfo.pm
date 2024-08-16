package Cpanel::SSLInfo;

# cpanel - Cpanel/SSLInfo.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Debug                        ();
use Cpanel::Locale                       ();
use Cpanel::AcctUtils::DomainOwner::BAMP ();
use Cpanel::Apache::TLS                  ();
use Cpanel::PwCache                      ();
use Cpanel::Set                          ();
use Cpanel::SSL::CABundleUtils           ();
use Cpanel::SSL::CABundleCache           ();
use Cpanel::SSL::Utils                   ();
use Cpanel::SSL::Verify                  ();
use Cpanel::SSL::Objects::CABundle       ();
use Cpanel::SSL::Objects::Certificate    ();
use Cpanel::StringFunc::SplitBreak       ();

my @ACCEPTABLE_VERIFY_ERRORS = qw(
  CERT_HAS_EXPIRED
  DEPTH_ZERO_SELF_SIGNED_CERT
  SELF_SIGNED_CERT_IN_CHAIN
);

#The number of seconds to allow for CERT_NOT_YET_VALID errors.
use constant CERT_NOT_YET_VALID_TOLERANCE => 300;

our $VERSION = '2.6';

# This is only set during a restore
# to prevent recreating the
# Cpanel::SSL::Verify object for each
# restored cert
our $SSL_VERIFY_SINGLETON;

my $locale;

*demunge_ssldata = \&Cpanel::SSL::Utils::demunge_ssldata;

sub SSLInfo_init { 1; }

sub getcrtdomain {
    my $crt = shift;
    $crt = demunge_ssldata($crt);

    my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text($crt);

    # scalar context for 11.34-- compat
    return wantarray ? ( 0, $parse ) : '' if !$ok;

    my @domains = ( $parse->{'subject'}{'commonName'} );

    # scalar context for 11.34-- compat
    return wantarray ? ( 1, $domains[0] ) : $domains[0];
}

#----------------------------------------------------------------------
# XXX XXX XXX
#
# You MUST verify the returned CA bundle with is_ssl_payload(), thus:
#
#   my $cab = ( Cpanel::SSLInfo::fetchcabundle($cert_string) )[2];
#   $cab_pem = $cab if Cpanel::SSLInfo::is_ssl_payload($cab);
#
sub fetchcabundle {
    my ($certificate) = @_;
    if ( !$certificate ) {
        Cpanel::Debug::log_warn('Missing certificate data');
        return;
    }
    $certificate = demunge_ssldata($certificate);
    my $cert_obj;
    eval { $cert_obj = Cpanel::SSL::Objects::Certificate->new( 'cert' => $certificate ) };
    if ($@) {
        Cpanel::Debug::log_warn($@);
        return;
    }
    if ( $cert_obj->issuer_text() eq $cert_obj->subject_text() ) {

        # Sorry, is required to preceed the string for legacy callers
        return ( $cert_obj->domain(), 'self', "Sorry, this certificate is self signed." );
    }

    my $provider;
    my $fetched_cabundle;

    my $crtdomain = $cert_obj->domain();

    try {
        if ( my $url = $cert_obj->caIssuers_url() ) {
            $fetched_cabundle = Cpanel::SSL::CABundleCache->load($url);
        }
    }
    catch {
        Cpanel::Debug::log_warn("Failed to fetch CA bundle information from certificate’s “authorityInfoAccess” extension: $_");
    };

    if ( !defined $fetched_cabundle ) {
        try {
            my $payload = Cpanel::SSL::CABundleUtils::fetch_cabundle_from_cpanel_repo($certificate);

            $provider         = $payload->{'name'};
            $fetched_cabundle = $payload->{'cabundle'};
        }
        catch {
            Cpanel::Debug::log_warn("Failed to fetch cabundle information from cabundle.cpanel.net: $_");
        };
    }

    my ( $ca_bundle, $rv_domain );

    if ($fetched_cabundle) {
        $ca_bundle = Cpanel::SSL::Utils::normalize_cabundle_order($fetched_cabundle);
        $rv_domain = $crtdomain;
    }

    # Sorry, is required to preceed the string for legacy callers
    $ca_bundle ||= "Sorry, no certificate authority bundle was found; however, you probably don't need one for this certificate ($crtdomain).";

    $provider ||= $cert_obj->issuer()->{'commonName'};

    return ( $rv_domain, $provider, $ca_bundle );
}

sub api2_fetchinfo {
    my %OPTS = @_;

    if ( !$OPTS{'domain'} && !$OPTS{'crtdata'} ) {
        $Cpanel::CPERROR{$Cpanel::context} = "fetchinfo requires either 'domain' or 'crtdata'";
    }

    my $result = fetchinfo( $OPTS{'domain'}, $OPTS{'crtdata'} );

    #Legacy compatibility
    if ( !$result->{'crt'} ) {
        $result->{'status'} = 0;
    }

    if ($result) {
        $Cpanel::CPERROR{$Cpanel::context} = $result->{'statusmsg'} if !$result->{'status'};
    }
    else {
        $Cpanel::CPERROR{$Cpanel::context} = "Invalid result returned from fetchinfo";
    }

    return [$result];
}

#This function only checks the user's datastore.
#
#Parameters:
#   0) The certificate's ID.
#   1) The user (defaults to $ENV{'REMOTE_USER'})
#
#Return is a single hashref of:
#   certificate: The certificate, PEM
#   key: The matching key, PEM (undef if there is no matching key)
#   subject.commonName_ip: The IP corresponding to the subject CN (undef if none)
sub fetch_crt_info {
    my ( $id, $user ) = @_;

    if ( !length $id ) {
        $locale ||= Cpanel::Locale->get_handle();
        return ( 0, $locale->maketext( 'You must provide the “[_1]”.', 'id' ) );
    }

    $user ||= $ENV{'REMOTE_USER'};

    my %retval = map { $_ => undef } qw(
      certificate
      key
      subject.commonName_ip
      is_self_signed
    );

    local $@;
    require Cpanel::SSLStorage::User;
    my $ssl_ds = eval { Cpanel::SSLStorage::User->new( user => $user ) };
    return ( 0, $@ ) if $@ || !ref $ssl_ds;

    my ( $ok, $certs_ar ) = $ssl_ds->find_certificates( id => $id );
    return ( 0, $certs_ar ) if !$ok;

    if (@$certs_ar) {
        my ( $ok, $text ) = $ssl_ds->get_certificate_text($id);
        return ( 0, $text ) if !$ok;

        $retval{'certificate'} = $text;

        my $keys_ar;
        ( $ok, $keys_ar ) = $ssl_ds->find_keys(
            %{ $certs_ar->[0] }{ 'modulus', 'ecdsa_curve_name', 'ecdsa_public' },
        );
        return ( 0, $keys_ar ) if !$ok;

        if (@$keys_ar) {
            ( $ok, $text ) = $ssl_ds->get_key_text( $keys_ar->[0]{'id'} );
            return ( 0, $text ) if !$ok;

            $retval{'key'} = $text;
        }

        $retval{'is_self_signed'}        = $certs_ar->[0]{'is_self_signed'};
        $retval{'subject.commonName_ip'} = _get_domain_http_ip( $certs_ar->[0]{'subject.commonName'} );
    }

    if ( $retval{'certificate'} ) {
        my ( $cert_domain, $ssl_provider, $ca_bundle ) = fetchcabundle( $retval{'certificate'} );
        if ( $ssl_provider && $ssl_provider eq 'self' ) {
            $ca_bundle = undef;
        }
        $retval{'cabundle'} = $ca_bundle;
    }

    return ( 1, \%retval );
}

#Find the best cert/key/cab for the given $domain,
#or return the key/cab for the given $query_cert.
#Also return the IP address for the given $domain (or the cert's first domain).
#
#SECURITY:
#$users is an arrayref of users whose home dir SSL storage is to search;
#if this is not provided and we're running as root (e.g., WHM), this will search
#the domain owner's homedir. Thus, there is potential for INFORMATION DISCLOSURE
#(e.g., a reseller searches on a domain that an uncontrolled user owns)
#if this function is not called correctly.
#
#By not passing a value for users the system will allow return of keys owned
#by root.  For this reason all calls to this function in whm must use
# Whostmgr::SSL::reseller_aware_fetch_sslinfo to avoid accidently creating
# an information discoslure hole.
sub fetchinfo {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $domain, $query_cert, $users ) = @_;
    #
    # SECURITY: If a user value is passed, we only look in that users storage
    #

    if ( !$domain && ( !$query_cert || _is_ssl_error_message($query_cert) ) ) {
        return { 'status' => 0, 'statusmsg' => 'No domain or certificate provided.', };
    }

    if ($query_cert) {
        $query_cert =~ s/BEGIN\s+CERTIFICATE/BEGIN CERTIFICATE/;
        $query_cert =~ s/END\s+CERTIFICATE/END CERTIFICATE/;
    }

    if ( $domain && ( $domain =~ m/\s/ || $domain =~ m/\.\./ || $domain =~ m/\// ) ) {
        return { 'status' => 0, 'statusmsg' => 'Invalid domain', };
    }
    elsif ($query_cert) {
        my ( $status, $ret ) = getcrtdomain($query_cert);
        return { 'status' => 0, 'statusmsg' => $ret } if !$status;

        $domain = $ret;
    }

    my $has_all_acl_and_root;

    if ( $> == 0 ) {

        #If we passed in a list of users whose homedirs to check, then
        #don't bother checking the domain owner.
        $has_all_acl_and_root = int !$users;

        if ( $users && !ref $users ) {
            $users = [$users];
        }

        $users ||= [];

        # Ensure that we look at the logged-in user as well
        if ( $ENV{'REMOTE_USER'} && !grep { $_ eq $ENV{'REMOTE_USER'} } @{$users} ) {
            push @{$users}, $ENV{'REMOTE_USER'};
        }
    }
    else {
        $has_all_acl_and_root = 0;
        $users                = [ Cpanel::PwCache::getusername() ];
    }

    my $domain_owner = Cpanel::AcctUtils::DomainOwner::BAMP::getdomainownerBAMP( $domain, { 'default' => '' } );
    #
    # SECURITY: if they don't pass in a list of users
    # then we allow looking in the sslstorage of the
    # user who owns the domain
    #
    if ( $has_all_acl_and_root && $domain ) {
        push @{$users}, $domain_owner if $domain_owner && !grep { $_ eq $domain_owner } @{$users};
    }

    # $users now has a list of users that we should use for the lookup
    my ( $key_text, $crt_user, $key_user );

    #
    # Lookup by certificate
    #
    if ( $query_cert && !_is_ssl_error_message($query_cert) ) {
        $crt_user = $> == 0 ? $ENV{'REMOTE_USER'} : Cpanel::PwCache::getusername();

        my ( $mod_ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text($query_cert);
        if ( !$mod_ok ) {
            return { status => 0, statusmsg => 'The certificate file is invalid.' };
        }

        foreach my $user ( @{$users} ) {    # if cPanel, will only be one user
            $key_text = _fetchsslkey( $domain, $user, $parse, $has_all_acl_and_root );
            if ( $key_text && _is_valid_key($key_text) ) {
                $key_user ||= $user;
                last;
            }
        }
    }

    #
    # Lookup by domain
    #
    else {
        foreach my $user ( @{$users} ) {
            $query_cert = fetchsslcrt( $domain, $user );
            if ( $query_cert && !_is_ssl_error_message($query_cert) ) {
                $crt_user ||= $user;
                last;
            }
        }

        if ( $query_cert && !_is_ssl_error_message($query_cert) ) {
            my ( $mod_ok, $parse ) = Cpanel::SSL::Utils::parse_certificate_text($query_cert);
            if ( !$mod_ok ) {
                return { status => 0, statusmsg => 'The certificate file is invalid.' };
            }

            foreach my $user ( @{$users} ) {    # if cPanel, will only be one user
                $key_text = _fetchsslkey( $domain, $user, $parse, $has_all_acl_and_root );
                if ( $key_text && _is_valid_key($key_text) ) {
                    $key_user ||= $user;
                    last;
                }
            }
        }
        elsif ($domain) {
            return { 'status' => 1, 'statusmsg' => "No certificate for the domain $domain could be found.", };
        }
        else {
            return { 'status' => 0, 'statusmsg' => 'Certificate not provided and no existing certificates located.', };
        }
    }

    my ( $cert_domain, $ssl_provider, $ca_bundle ) = fetchcabundle($query_cert) if $query_cert;

    if ( $ssl_provider && $ssl_provider eq 'self' ) {
        $ca_bundle = '';
    }

    return {
        'crt'       => $query_cert,
        'cab'       => $ca_bundle,
        'key'       => $key_text,
        'status'    => 1,
        'statusmsg' => 'ok',
        'domain'    => $domain,
        'ip'        => _get_domain_http_ip($domain),
        'user'      => $domain_owner,

        # crt_origin and key_origin
        # show where the crt and key
        # came from.
        'crt_origin'     => $crt_user,
        'key_origin'     => $key_user,
        'searched_users' => $users,
    };
}

sub _get_domain_http_ip {
    my ($domain) = @_;

    my $base_domain;

    if ( $domain =~ tr{*}{} ) {
        $base_domain = $domain;
        $base_domain =~ s/^\*\.//;    # Cleanup any wildcards that would cause problem for the ip lookup.
    }

    my $user_owner;

    if ( !$> ) {
        require Cpanel::Domain::Owner;
        $user_owner = Cpanel::Domain::Owner::get_owner_or_undef($domain);
        return undef if !$user_owner;
    }

    local $Cpanel::user = $user_owner if defined $user_owner;

    require Cpanel::UserDomainIp;

    #
    # Prefer the IP the ssl host is installed on in case they
    # do not match the IP the non-ssl host is installed on.
    #
    my $ip = Cpanel::UserDomainIp::getdomainip_ssl($domain);

    # Fall back to the base domain’s SSL vhost if $domain is a wildcard.
    $ip ||= $base_domain && Cpanel::UserDomainIp::getdomainip_ssl($base_domain);

    #--------------------
    # NOTE: We used to try a DNS resolution to get an IP address below
    # if we had no locally-stored IP address.
    #--------------------

    # Still nothing? Then fall back to the given domain’s non-SSL vhost.
    $ip ||= Cpanel::UserDomainIp::getdomainip($domain);

    # As a last resort, fall back to the base domain’s non-SSL vhost.
    $ip ||= $base_domain && Cpanel::UserDomainIp::getdomainip($base_domain);

    return $ip;
}

sub fetchsslcrt {
    my ( $domain, $user ) = @_;

    # Sorry, is required to preceed the string for legacy callers
    return "Sorry, fetchsslcrt requires a user be passed in order to fetch a certificate" unless length $user;

    my $sslcrt;

    require Cpanel::SSLStorage::User;
    my $sslstorage = Cpanel::SSLStorage::User->new( user => $user );

    # Sorry, is required to preceed the string for legacy callers
    return "Sorry, fetchsslcrt could not create an sslstorage object for the requested user" unless $sslstorage;

    my $cert_sorter_func = sub {
        return $a->{'is_self_signed'} <=> $b->{'is_self_signed'} || $b->{'not_after'} <=> $a->{'not_after'} || Cpanel::SSL::Utils::compare_encryption_strengths( $b, $a ) || Cpanel::SSL::Utils::hashing_function_strength_comparison( $b->{'signature_algorithm'}, $a->{'signature_algorithm'} );
    };
    ## case 34710: fetchinfo for domain.net and www.domain.net, with the user's choice having
    ##   precedence.
    my @domains = ( $domain, ( $domain =~ m/^www\.(.*)/ ? $1 : "www.$domain" ) );
    for my $domain (@domains) {
        my ( $ok, $certs ) = $sslstorage->find_certificates( 'domains' => $domain );

        #Sort by:
        #   prefer CA-signed
        #   prefer latest expiration
        #   prefer longer modulus ("key size")
        #   prefer stronger signature algorithm
        #
        #NOTE: The above implies that, for the modulus length or
        #signature algorithm to matter at all,
        #two certs would have to have the exact same expiration time.
        my @potential_certs;
        #
        if ( $ok && $certs && @$certs ) {
            push @potential_certs, @$certs;
        }
        if ( ( $domain =~ tr/\.// ) >= 2 ) {    # Try matching a matching wildcard certificate, however wildcard certs need at least 2 dots
            my $matching_wildcard_domain = $domain;
            $matching_wildcard_domain =~ s/^[^\.]+/\*/;

            ( $ok, $certs ) = $sslstorage->find_certificates( 'domains' => $matching_wildcard_domain );
            if ( $ok && $certs && @$certs ) {
                push @potential_certs, @$certs;
            }
        }

        if (@potential_certs) {
            $sslcrt = ( sort $cert_sorter_func @potential_certs )[0];
        }

        if ( $sslcrt && $sslcrt->{'id'} ) {
            ( $ok, $sslcrt ) = $sslstorage->get_certificate_text( $sslcrt->{'id'} );
            if ( !$ok ) {
                $sslcrt = undef;
            }
        }

        #No root access needed for this.
        if ( !$sslcrt ) {
            require Cpanel::Config::WebVhosts;

            try {
                my $wvh     = Cpanel::Config::WebVhosts->load($user);
                my $vh_name = $wvh->get_vhost_name_for_domain($domain);
                $vh_name ||= $wvh->get_vhost_name_for_ssl_proxy_subdomain($domain);

                if ($vh_name) {
                    ($sslcrt) = Cpanel::Apache::TLS->get_certificates($vh_name);
                }
            }
            catch {
                # Sorry, is required to preceed the string for legacy callers
                $sslcrt = "Sorry, an error occurred while trying to find an installed certificate for “$domain”: $_";
            };
        }

        last if $sslcrt;
    }

    if ($sslcrt) {
        $sslcrt =~ s/\r//g;
    }
    else {
        # Sorry, is required to preceed the string for legacy callers
        $sslcrt = "Sorry, no ssl certificate (crt) file was found for the domain $domain.";
    }

    return $sslcrt;
}

sub _fetchsslkey {
    my ( $domain, $user, $cert_obj, $has_all_acl_and_root ) = @_;

    my $sslkey;

    require Cpanel::SSLStorage::User;
    my ( $ok, $sslstorage ) = Cpanel::SSLStorage::User->new( user => $user );

    # error message is returned if things went wrong
    return $sslstorage unless $ok;

    ( $ok, my $keys_ar ) = $sslstorage->find_keys(
        map { $_ => $cert_obj->$_() } (
            'modulus',
            'ecdsa_curve_name',
            'ecdsa_public',
        ),
    );

    if ( $ok && $keys_ar && @$keys_ar ) {
        my $id = $keys_ar->[0]{'id'};
        my ( $ok, $text ) = $sslstorage->get_key_text($id);
        if ( $ok && $text ) {
            $sslkey = $text;
        }
    }

    if ( !$sslkey ) {

        #Check service SSL for a key that matches the given modulus.
        #-- only for root, of course!
        if ( $> == 0 ) {
            if ($has_all_acl_and_root) {
                local $@;
                local $!;

                require Cpanel::SSLCerts;

                for my $service ( Cpanel::SSLCerts::available_services() ) {
                    my $file_ref = Cpanel::SSLCerts::fetchSSLFiles( 'service' => $service );
                    if ( $file_ref->{'key'} ) {
                        my ( $ok, $key_obj ) = Cpanel::SSL::Utils::parse_key_text( $file_ref->{'key'} );

                        if ($ok) {
                            my $match_ok;

                            if ( $cert_obj->modulus() ) {
                                $match_ok = ( $key_obj->modulus() // q<> ) eq $cert_obj->modulus;
                            }
                            elsif ( $cert_obj->ecdsa_curve_name && $cert_obj->ecdsa_public ) {
                                $match_ok = $key_obj->ecdsa_curve_name() eq $cert_obj->ecdsa_curve_name;
                                $match_ok &&= $key_obj->ecdsa_public() eq $cert_obj->ecdsa_public;
                            }
                            else {
                                die 'no RSA modulus nor ECDSA data!';
                            }

                            if ($match_ok) {
                                $sslkey = $file_ref->{'key'};
                                last;
                            }
                        }
                    }
                }
            }
        }
        elsif ( my $modulus = $cert_obj->modulus ) {
            require Cpanel::AdminBin;
            $sslkey = Cpanel::AdminBin::adminstor( 'ssl', 'FETCHBYMODULUS', { modulus => $modulus } );

            if ( _is_ssl_error_message($sslkey) ) {    # hack to glue errors together
                $sslkey .= "\n" unless $sslkey =~ m/[\s\n]$/;
                $sslkey .= "No SSL key file was found for the modulus $modulus.\n";
            }
        }
        elsif ( $cert_obj->ecdsa_curve_name && $cert_obj->ecdsa_public ) {
            require Cpanel::AdminBin::Call;
            $sslkey = Cpanel::AdminBin::Call::call( 'ssl_call', 'FETCH_INSTALLED_KEY_BY_ECDSA_CURVE_AND_POINT', $cert_obj->ecdsa_curve_name, $cert_obj->ecdsa_public );
        }
        else {
            die 'no RSA modulus nor ECDSA data!';
        }

        if ( $sslkey && $sslkey !~ m{---} ) {

            # Sorry, is required to preceed the string for legacy callers
            $sslkey = "Sorry, $sslkey";    # evil hack
        }
    }

    if ( !$sslkey ) {

        # Sorry, is required to precede the string for legacy callers
        $sslkey = "Sorry, no SSL key file was found for the domain $domain.";
    }

    $sslkey =~ s/\r//g;
    return $sslkey;
}

sub getcabundle {
    my ( $domain, $crt, $cpanelmode ) = @_;
    if ( !$cpanelmode ) {
        my %FORM = %{$main::formref};
        $crt    = $FORM{'crt'};
        $domain = $FORM{'domain'};
    }

    $crt = demunge_ssldata($crt);
    my $bundle;
    my $cab;
    ( $domain, $bundle, $cab ) = fetchcabundle($crt);
    print "CRT DOMAIN: $domain\n";
    print "BUNDLE: $bundle\n";

    print qq{<html>
   <script>};
    print "parent.frames.installsslf.document.mainform.cabundle.value = \"";
    my @SSLKEY = split( /\n/, $cab );
    foreach my $line (@SSLKEY) {
        $line =~ s/[\r|\n]*//g;
        print "$line\\n";
    }
    print "\"\n";
    print qq{parent.frames.installsslf.document.mainform.go.disabled = false;
   </script>
   </html>};

    return;
}

#Returns:
#   - status (boolean)
#   - message
#   - cert parse (if successful)
#   - key parse (if successful)
#   - verify object
#
sub verifysslcert {    ##no critic qw(ProhibitExcessComplexity)
    shift;             #unused first argument
    my $crt   = shift;
    my $key   = shift;
    my $cab   = shift;
    my $quiet = shift || '';

    # This used to accept a “plain” flag that governed whether the return
    # was plain text (1) or HTML (0). As of August 2020 that flag was always
    # passed, so plain text is now the only return format.

    my $br = "\n";
    if ( $crt !~ /---/ ) {

        # Sorry, is required to preceed the string for legacy callers
        return ( 0, "Sorry, that is not a valid certificate\n" );
    }
    if ( $crt =~ /CERTIFICATE REQUEST/ ) {

        # Sorry, is required to preceed the string for legacy callers
        return ( 0, "Sorry, we need the certificate, not the certificate request\n" );
    }
    if ( $crt !~ /BEGIN CERTIFICATE/ ) {

        # Sorry, is required to preceed the string for legacy callers
        return ( 0, "Sorry, Invalid certificate passed to verifysslcert (missing BEGIN CERTIFICATE)\n" );
    }
    print "Attempting to verify your certificate.....\n" if !$quiet;

    my $now = time();

    if ( $key =~ /Proc-Type: 4,ENCRYPTED/i ) {
        my $msg = qq{openssl rsa -in <original key file> -out <new key file>};
        return ( 0, "${br}This key file is encrypted with a password. You must use openssl to decrypt this key first!${br}$msg" );
    }

    my ( $c_ok, $c_parse ) = Cpanel::SSL::Utils::parse_certificate_text($crt);
    if ( !$c_ok ) {
        return ( 0, "This certificate cannot be parsed ($c_parse). It may be corrupt or in an unrecognized format." );
    }

    my ( $k_ok, $k_parse ) = Cpanel::SSL::Utils::parse_key_text($key);
    if ( !$k_ok ) {
        return ( 0, 'This key cannot be parsed. It may be corrupt or in an unrecognized format.' );
    }

    my $match_yn = $c_parse->{'key_algorithm'} eq $k_parse->{'key_algorithm'};

    if ($match_yn) {
        if ( $c_parse->{'key_algorithm'} eq 'rsaEncryption' ) {
            $match_yn = $c_parse->{'modulus'} eq $k_parse->{'modulus'};
        }
        elsif ( $c_parse->{'key_algorithm'} eq 'id-ecPublicKey' ) {
            $match_yn = $c_parse->{'ecdsa_curve_name'} eq $k_parse->{'ecdsa_curve_name'};
            $match_yn &&= $c_parse->{'ecdsa_public'} eq $k_parse->{'ecdsa_public'};
        }
        else {
            die "bad algorithm: $c_parse->{'key_algorithm'}";
        }
    }

    if ( !$match_yn ) {
        my $formatter_cr = sub ($txt) {
            my $formatted = Cpanel::StringFunc::SplitBreak::textbreak($txt);
            $formatted =~ s/\s+/\n/g;
            return $formatted;
        };

        my @pieces = (
            [
                'Key',
                $key,
                $k_parse,
            ],
            [
                'Certificate',
                $crt,
                $c_parse,
            ],
        );

        my @report;

        for my $piece_ar (@pieces) {
            my ( $label, $pem, $parse ) = @$piece_ar;

            my ( $detail_name, $detail_value );

            if ( $parse->{'key_algorithm'} eq 'rsaEncryption' ) {
                $detail_name  = 'Modulus';
                $detail_value = $parse->{'modulus'};
            }
            elsif ( $parse->{'key_algorithm'} eq 'id-ecPublicKey' ) {
                $detail_name  = "Public Point ($parse->{'ecdsa_curve_name'})";
                $detail_value = $parse->{'ecdsa_public'};
            }
            else {
                die "bad algorithm: $parse->{'key_algorithm'}";
            }

            $detail_value = $formatter_cr->($detail_value);

            push @report, (
                "$label:"              => $pem,
                "$label $detail_name:" => $detail_value,
                q<>, q<>,
            );
        }

        pop @report;

        my $msg = join( $br, @report );

        return ( 0, "The key does not match the certificate. Please try another key.${br}${br}$msg" );
    }

    my $ssl_verify = $SSL_VERIFY_SINGLETON || Cpanel::SSL::Verify->new();

    my @cabundle;

    if ( $cab && $cab =~ /BEGIN CERTIFICATE/ ) {

        $cab = Cpanel::SSL::Objects::CABundle->new( cab => $cab );

        my ( $ok, $chain_ar ) = $cab->get_chain_without_trusted_root_certs();
        return ( 0, $chain_ar ) if !$ok;

        @cabundle = reverse @$chain_ar;
    }

    my @cert_chain = ( $crt, map { $_->text() } @cabundle );

    my $crt_verify = $ssl_verify->verify(@cert_chain);

    my $err_name = $crt_verify->get_error();

    my $verify_ok = 1;

    #As of 11.56, we need to check both.
    $locale ||= Cpanel::Locale->get_handle();

    my @msg;
    for my $depth ( 0 .. $crt_verify->get_max_depth() ) {
        my @errs = $crt_verify->get_errors_at_depth($depth);

        @errs = Cpanel::Set::difference(
            \@errs,
            \@ACCEPTABLE_VERIFY_ERRORS,
        );

      ERR:
        for my $err (@errs) {

            #We tolerate cases of small clock skews for otherwise valid certs.
            #Note that we only warn for otherwise-valid certs because an
            #invalid cert could easily just be forged.
            if ( $err eq 'CERT_NOT_YET_VALID' && 1 == @errs ) {
                my $is_acceptable;

                my $crt_obj = Cpanel::SSL::Objects::Certificate->new(
                    cert => $cert_chain[$depth],
                );

                my $not_before = $crt_obj->not_before();

                my $now = time;

                push @msg, (
                    $locale->maketext(
                        'An [asis,SSL/TLS] certificate failed verification because the system’s time is [datetime,_1,datetime_format_medium], and the certificate is not valid until [datetime,_2,datetime_format_medium]. The certificate is otherwise valid. The system’s time may be incorrect. Try either the “[_3]” or “[_4]” command to fix this problem.',
                        $now, $not_before, 'rdate -s rdate.cpanel.net', 'ntpclient -s -h pool.ntp.org'
                    ),
                );

                if ( ( $not_before - $now ) < CERT_NOT_YET_VALID_TOLERANCE ) {
                    push @msg, $locale->maketext( 'Because the time difference is less than [quant,_1,second,seconds], the system will ignore this verification error.', CERT_NOT_YET_VALID_TOLERANCE );

                    $is_acceptable = 1;
                }

                next ERR if $is_acceptable;
            }

            $verify_ok = 0;
            last;
        }
    }

    if ($verify_ok) {
        unshift @msg, $locale->maketext("Certificate verification passed.");
        return ( 1, join( ' ', @msg ), $c_parse, $k_parse, $crt_verify );
    }
    else {
        my $message      = $locale->maketext("Certificate verification failed!") . ' ' . join( ' ', @msg );
        my @errors2catch = qw{ UNABLE_TO_GET_ISSUER_CERT UNABLE_TO_VERIFY_LEAF_SIGNATURE };

        if ( !@cabundle && grep { $_ eq $err_name } @errors2catch ) {
            $message .= ' ' . $locale->maketext('The system did not find the Certificate Authority Bundle that matches this certificate.');
            my $cert_obj;
            local $@;
            eval {
                require Cpanel::SSL::Objects::Certificate;
                $cert_obj = Cpanel::SSL::Objects::Certificate->new( 'cert' => $crt );
            };
            if ($cert_obj) {
                if ( my $issuer = $cert_obj->issuer() ) {

                    #We used to use commonName here exclusively, but
                    #CloudFlare doesn’t use commonName. This accommodates
                    #them as well as whatever other CAs may be out there that
                    #behave that way.
                    my $name = $issuer->{'commonName'} || $issuer->{'organizationalUnitName'};

                    if ( $issuer->{'organizationName'} ) {
                        $message .= ' ' . $locale->maketext( "Contact “[_1]” to obtain the Certificate Authority Bundle for “[_2]”.", $issuer->{'organizationName'}, $name );
                    }
                    else {
                        $message .= ' ' . $locale->maketext( "Contact “[_1]” to obtain the Certificate Authority Bundle.", $name );
                    }
                }
            }
            else {
                $message .= ' ' . $locale->maketext('Supply the Certificate Authority Bundle to proceed.');
            }
            return ( 0, $message );
        }
        elsif ( @cabundle && $err_name eq 'UNABLE_TO_GET_ISSUER_CERT_LOCALLY' ) {
            $message .= ' ' . $locale->maketext("The system did not find the root certificate that corresponds to the supplied Certificate Authority Bundle’s intermediate certificate. Please supply a full Certificate Authority Bundle with the root certificate included.");
            return ( 0, $message );
        }

        # $err_name will always be unlocalized, as it is the direct output from openssl verify calls through Net::SSLeay.
        return ( 0, $message . ' ' . $err_name );
    }
}

sub is_ssl_payload {
    my ($msg) = @_;

    return 0 if !$msg || _is_ssl_error_message($msg);

    return 1;
}

our %API = (
    fetchinfo => {
        modify      => 'angle_bracket_encode',
        xss_checked => 1,
        allow_demo  => 1,
    }
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

sub _strip_ssl_warnings {
    my $verify = shift;
    $verify =~ s/stdin:[\t\s]*//g;
    $verify =~ s/[\r\n]*$//g;
    $verify =~ s/error\s+\d+\s+at\s+\d+\s+depth\s+lookup:unable\s+to\s+get\s+local\s+issuer\s+certificate//g;
    $verify =~ s/error\s+\d+\s+at\s+\d+\s+depth\s+lookup:self\+signed\+certificate/\(certificate is self signed\)/g;
    $verify =~ s/[\r\n]+$//g;
    return $verify;
}

sub _is_ssl_error_message {
    my ($msg) = @_;

    #
    #  Eventually we will replace this with a more sane way of checking for
    #  invalid data.  However this is a placeholder to remind us of this
    #  design flaw (even if it works just fine).
    #
    return 1 if length $msg && $msg =~ m{sorry\s*,}i;    # We check for a comma since 'sorry' is a valid base64 seq.
    return 0;
}

sub _is_valid_key {
    my ($key) = @_;
    my ( $ok, $parse ) = Cpanel::SSL::Utils::parse_key_text($key);
    return $ok;
}

1;
