package Whostmgr::SSL;

# cpanel - Whostmgr/SSL.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::ArrayFunc::Uniq                  ();
use Cpanel::AcctUtils::DomainOwner::Tiny     ();
use Cpanel::Config::LoadUserOwners           ();
use Cpanel::Config::Httpd::IpPort            ();
use Cpanel::CountryCodes                     ();
use Cpanel::DIp::IsDedicated                 ();
use Cpanel::DIp::Owner                       ();
use Cpanel::Encoder::Tiny                    ();
use Cpanel::Hostname                         ();
use Cpanel::HttpUtils::Vhosts::PrimaryReader ();
use Cpanel::IP::Configured                   ();
use Cpanel::Debug                            ();
use Cpanel::TempFile                         ();
use Cpanel::Template::Simple                 ();
use Cpanel::Validate::Domain                 ();
use Cpanel::Validate::EmailRFC               ();
use Whostmgr::ACLS                           ();
use Whostmgr::AcctInfo::Owner                ();
use Whostmgr::Theme                          ();
use Cpanel::NAT                              ();
use Cpanel::WebVhosts::ProxySubdomains       ();
use Cpanel::WebVhosts::AutoDomains           ();

use constant {
    DOMAIN        => 0,
    DOMAIN_OWNER  => 1,
    DOMAIN_TYPE   => 3,
    BASE_DOMAIN   => 4,
    DOCUMENT_ROOT => 5,
    SSL_IP        => 7,
    IPV6          => 8,

};

my @subject_components = qw(
  countryName
  emailAddress
  localityName
  organizationName
  organizationalUnitName
  stateOrProvinceName
);

my %cert_parameters = (
    'domains' => {
        'required' => 1,
        'valid'    => sub {
            my ($value) = @_;

            my $domains_ar = _convert_domains_string_to_array_ref($value);

            for my $domain (@$domains_ar) {
                my ( $status, $statusmsg ) = Cpanel::Validate::Domain::validwildcarddomain($domain);
                return ( 0, $statusmsg ) if !$status;
            }

            return $domains_ar;
        },
    },
    'pass' => {
        'required' => 0,
        'valid'    => sub {
            my ($value) = @_;
            if ($value) {
                my $pass_length = length $value;
                if ( $pass_length > 20 ) {
                    return wantarray ? ( 0, 'The specified password must be less than 20 characters.' ) : 0;
                }
                elsif ( $pass_length < 4 ) {
                    return wantarray ? ( 0, 'The specified password must be greater than 3 characters.' ) : 0;
                }

                #TODO: add test for alphanumeric
            }
            return $value;
        },
    },
    'countryName' => {
        'required' => 0,
        'valid'    => sub {
            my ($value) = @_;
            return if !$value;

            my $country_codes_ar = Cpanel::CountryCodes::COUNTRY_CODES();
            if ( !( grep { $_ eq $value } @$country_codes_ar ) ) {
                return wantarray ? ( 0, "“$value” is not a valid country code." ) : 0;
            }

            return $value;
        },
    },
    'stateOrProvinceName' => {
        'required' => 0,
        'valid'    => sub {
            my ($value) = @_;
            return if !length $value;
            if ( length $value < 1 ) {
                return wantarray ? ( 0, 'The specified state must be at least 1 letter long.' ) : 0;
            }
            return $value;
        },
    },
    'localityName' => {
        'required' => 0,
        'valid'    => sub {
            my ($value) = @_;
            return if !length $value;
            if ( length $value < 1 ) {
                return wantarray ? ( 0, 'The specified city must be at least 1 letter long.' ) : 0;
            }
            return $value;
        },
    },
    'organizationName' => {
        'required' => 0,
        'valid'    => sub {
            my ($value) = @_;
            return if !length $value;
            my $co_length = length $value;
            if ( $co_length < 1 ) {
                return wantarray ? ( 0, 'The specified company must be at least 1 character long.' ) : 0;
            }
            if ( $co_length > 64 ) {    # ub-organization-name = 64
                return wantarray ? ( 0, 'The specified company must be no longer than 64 characters.' ) : 0;
            }
            return $value;
        },
    },
    'organizationalUnitName' => {
        'required' => 0,
        'valid'    => sub {
            my ($value) = @_;
            return if !length $value;
            my $cod_length = length $value;
            if ( $cod_length < 1 ) {
                return wantarray ? ( 0, 'The specified division must be at least 1 character long.' ) : 0;
            }
            if ( $cod_length > 64 ) {    # ub-organizational-unit-name = 64
                return wantarray ? ( 0, 'The specified division must be no longer than 64 characters.' ) : 0;
            }
            return $value;
        },
    },
    'emailAddress' => {
        'required' => 0,
        'valid'    => sub {
            my ($value) = @_;
            return ( 0, 'No Value' ) if !$value;
            my $email_length = length $value;
            return ( 0, 'The contact email address is invalid.' . $value ) if !Cpanel::Validate::EmailRFC::is_valid($value);
            return $value;
        },
    },
    'xemail' => {
        'required' => 0,
        'valid'    => sub {
            my ($value) = @_;
            return                                               if !$value;
            return ( 0, 'The notify email address is invalid.' ) if !Cpanel::Validate::EmailRFC::is_valid($value);
            return $value;
        },
    },
);

sub validate_cert_parameters {
    my $args = shift;
    if ( !defined $args || ref $args ne 'HASH' ) {
        Cpanel::Debug::log_warn('Invalid argument');
        return;
    }

    foreach my $item ( sort keys %cert_parameters ) {
        if ( !length $args->{$item} ) {
            next if !$cert_parameters{$item}{'required'};

            my $msg = "Missing required parameter: $item.";
            Cpanel::Debug::log_warn($msg);
            return wantarray ? ( 0, $msg ) : 0;
        }

        my ( $value, $message ) = $cert_parameters{$item}{'valid'}->( $args->{$item} );

        if ( !$value ) {
            if ( !$message ) {
                $message = "Invalid parameter $item";
            }
            Cpanel::Debug::log_warn($message);
            return wantarray ? ( 0, $message ) : 0;
        }
    }
    return 1;
}

sub _convert_domains_string_to_array_ref {
    my $domains_str = shift;

    $domains_str =~ s{\A\s+|\s+\z}{}g;
    return if !$domains_str;

    return [ split m{[;,\s]+}, $domains_str ];
}

sub generate (%args) {
    require Cpanel::SSL::Legacy;
    my $key_pem = Cpanel::SSL::Legacy::generate_key_from_keysize_and_keytype(
        $ENV{'REMOTE_USER'},
        @args{ 'keysize', 'keytype' },
    );

    return _generate_with_key( $key_pem, %args );
}

sub _generate_with_key ( $key, %args ) {
    my $output = { 'status' => 0, 'message' => '', };

    if ( !length $key ) {
        $output->{'message'} = q[Failed to generate key];
        return $output;
    }

    my $skip_certificate = $args{'skip_certificate'};

    if ( !$args{'sendemail'} ) {
        $args{'xemail'} = 'root@localhost';

        #if this is not set validation will fail we will not actually use this value
    }

    if ( $args{'countryName'} ) {
        $args{'countryName'} =~ tr{a-z}{A-Z};
    }

    my ( $status, $message ) = validate_cert_parameters( \%args );
    if ( !$status ) {
        $output->{'message'} = $message;
        return $output;
    }

    $args{'domains'} =~ s{\A\s+|\s+\z}{}g;
    $args{'domains'} = _convert_domains_string_to_array_ref( $args{'domains'} );

    my $tfile = Cpanel::TempFile->new();
    my ( $temp_path, $temp_fh ) = $tfile->file();
    print {$temp_fh} $key;
    close $temp_fh;

    require Cpanel::OpenSSL;
    my $openssl = Cpanel::OpenSSL->new();
    if ( !$openssl ) {
        $output->{'message'} = 'Failed to initialize OpenSSL object. There is a problem with your OpenSSL installation.';
        return $output;
    }

    my $ssl_res;

    my $cert;
    if ( !$skip_certificate ) {
        $ssl_res = $openssl->generate_cert(
            {
                'keyfile' => $temp_path,
                ( map { $_ => $args{$_} } ( 'domains', @subject_components ) ),
            }
        );
        if ( !$ssl_res->{'status'} ) {
            $output->{'message'} = "Failed to generate certificate ($ssl_res->{'message'})";
            return $output;
        }
        $cert = $ssl_res->{'stdout'};
    }

    $ssl_res = $openssl->generate_csr(
        {
            'keyfile'  => $temp_path,
            'password' => $args{'pass'},
            ( map { $_ => $args{$_} } ( 'domains', @subject_components ) ),
        }
    );
    if ( !$ssl_res->{'status'} ) {
        $output->{'message'} = 'Failed to generate certificate signing request: <pre>' . Cpanel::Encoder::Tiny::safe_html_encode_str( $ssl_res->{'stderr'} ) . '</pre>';
        return $output;
    }
    my $csr = $ssl_res->{'stdout'};

    require Cpanel::SSLStorage::User;

    #Now that we have all of the components, we add to the user's datastore.
    my ( $ok, $msg );
    ( $ok, my $sslstorage ) = Cpanel::SSLStorage::User->new( user => $ENV{'REMOTE_USER'} );
    if ( !$ok ) {
        $output->{'message'} = $sslstorage;
        return $output;
    }

    my ( $cert_id, $cert_domains, $cert_path, $csr_id, $csr_path, $key_id, $key_path );

    my $friendly_name;

    if ($skip_certificate) {
        $ok = 1;

        #No friendly-name in this case … hope that’s ok?
    }
    else {
        ( $ok, $msg ) = $sslstorage->add_certificate( text => $cert );
        if ($ok) {
            $cert_id       = $msg->{'id'};
            $cert_domains  = $msg->{'domains'};
            $friendly_name = $msg->{'friendly_name'};
            $cert_path     = $sslstorage->get_certificate_path($cert_id);
        }
    }

    if ($ok) {
        ( $ok, $msg ) = $sslstorage->add_csr( text => $csr, friendly_name => $friendly_name );
        if ($ok) {
            $csr_id   = $msg->{'id'};
            $csr_path = $sslstorage->get_csr_path($csr_id);

            $friendly_name ||= $msg->{'friendly_name'};

            ( $ok, $msg ) = $sslstorage->add_key( text => $key, friendly_name => $friendly_name );
            if ($ok) {
                $key_id   = $msg->{'id'};
                $key_path = $sslstorage->get_key_path($key_id);

            }
        }
    }
    if ( !$ok ) {
        $output->{'message'} = $msg;
        return $output;
    }

    my $sender_host = Cpanel::Hostname::gethostname();
    my $sender      = $ENV{'REMOTE_USER'};
    if ( !$sender || $sender eq 'root' ) {
        $sender = 'cpanel';
    }

    $output->{'status'}      = 1;
    $output->{'message'}     = $skip_certificate ? 'Key and CSR generated OK' : 'Key, Certificate, and CSR generated OK';
    $output->{'key'}         = $key;
    $output->{'cert'}        = $cert;
    $output->{'cert_id'}     = $cert_id;
    $output->{'csr'}         = $csr;
    $output->{'csr_id'}      = $csr_id;
    $output->{'keyfile'}     = $key_path;
    $output->{'key_id'}      = $key_id;
    $output->{'certfile'}    = $cert_path;
    $output->{'csrfile'}     = $csr_path;
    $output->{'sender'}      = $sender;
    $output->{'sender_host'} = $sender_host;

    if ( $args{'sendemail'} && $args{'xemail'} ) {
        my $domains_list;

        local $@;
        if ( eval { require Cpanel::Locale } ) {
            my $locale = Cpanel::Locale->get_handle();
            $domains_list = $locale->list_and($cert_domains);
        }
        else {
            $domains_list = join( q{, }, @$cert_domains );
        }

        $output->{'args'} = { %args, domains_list => $domains_list };
        my %branding = (
            'branding' => Whostmgr::Theme::gettheme() || undef,
            'reseller' => $ENV{'REMOTE_USER'},
            'template' => 'generate_csr_results',
        );
        my $mail_message = Cpanel::Template::Simple::process_template( 'messages', $output, \%branding );

        require Cpanel::SafeRun::Full;
        my $email_results = Cpanel::SafeRun::Full::run( 'program' => '/usr/local/cpanel/bin/sendmail_cpanel', 'args' => [ '-f', $sender . '@' . $sender_host, '-t' ], 'stdin' => $$mail_message, );
        if ( !$email_results->{'status'} || $email_results->{'stderr'} ) {
            $output->{'email_status'} = 0;
            $output->{'email_message'} .= 'Failed to send the email containing the Certificate, Private Key and Certificate Signing Request to ' . Cpanel::Encoder::Tiny::safe_html_encode_str( $args{'xemail'} );
            $output->{'email_message'} .= '; ' . Cpanel::Encoder::Tiny::safe_html_encode_str( $email_results->{'stderr'} ) if $email_results->{'stderr'};
        }
        else {
            $output->{'email_status'}  = 1;
            $output->{'email_message'} = 'An email containing the Certificate, Private Key and Certificate Signing Request has been sent to ' . Cpanel::Encoder::Tiny::safe_html_encode_str( $args{'xemail'} );
        }
    }

    return $output;
}

#Accepts named arguments:
#   user (optional): defaults to $ENV{'REMOTE_USER'}
#   registered (boolean): Only report registered domains.
#
#NOTE: This only looks in the given user's userland SSL datastore.
#If reseller "god", who owns "mortal", is the user passed in, this will
#not check "mortal"'s data store.
sub list_cert_domains_with_owners {
    my %opts = @_;

    my ( $user, $only_want_registered_domains ) = @opts{qw(user registered)};

    $user ||= $ENV{'REMOTE_USER'};

    my @RSD;

    my ( $ok, $sslstorage, $certs );

    require Cpanel::SSLStorage::User;
    ( $ok, $sslstorage ) = Cpanel::SSLStorage::User->new( user => $user );
    return ( 0, $sslstorage ) if !$ok;

    ( $ok, $certs ) = $sslstorage->find_certificates();
    return ( 0, $certs ) if !$ok;

    for my $cert (@$certs) {
        my ( $domain, $domains, $self_signed ) = @{$cert}{qw(subject.commonName domains is_self_signed)};
        $self_signed = $self_signed ? 1 : 0;

        my @domain_owners;
        for my $cur_dom (@$domains) {

            # Skip invalid domains with a light check
            # since APNS certs will have a :
            # in the domain field which makes
            # getdomainowner fail
            # Ex: APSP:62afcac4-......
            #
            # This check was copied from
            # Cpanel::Userdomains::CORE
            #
            next if $cur_dom =~ tr{_*.a-z0-9-}{}c;

            my $domain_owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $cur_dom, { 'default' => undef } );
            if ( $domain_owner && $user ne $domain_owner && !Whostmgr::AcctInfo::Owner::checkowner( $user, $domain_owner ) ) {
                $domain_owner = undef;
            }

            push @domain_owners, $domain_owner;
        }

        my $registered = $domain_owners[0] ? 1 : 0;
        next if $only_want_registered_domains && !$registered;

        push @RSD,
          {
            'domain'                  => $domain,
            'domains'                 => $domains,
            'domain_owners'           => \@domain_owners,
            'id'                      => $cert->{'id'},
            'friendly_name'           => $cert->{'friendly_name'},
            'issuer.organizationName' => $cert->{'issuer.organizationName'},
            'is_self_signed'          => $self_signed,
            'not_after'               => $cert->{'not_after'},
            'registered'              => $registered,

            %{$cert}{ 'key_algorithm', 'modulus_length', 'ecdsa_curve_name' },
          };
    }

    return ( 1, \@RSD );
}

sub fetch_ssl_vhosts {
    my %OPTS     = @_;
    my $has_root = Whostmgr::ACLS::hasroot();

    my %sharedips;
    if ( Whostmgr::ACLS::hasroot() ) {
        require Cpanel::DIp;
        %sharedips = Cpanel::DIp::get_all_shared_ips();
    }
    else {
        %sharedips = map { $_ => 1 } @{ Cpanel::DIp::IsDedicated::getsharedipslist( $ENV{'REMOTE_USER'} ) };
    }

    require Cpanel::Apache::TLS::Index;

    my $apache_tls_idx = Cpanel::Apache::TLS::Index->new();

    require Cpanel::Time::ISO;

    my $all_records  = $apache_tls_idx->get_all_ar();
    my %vhost_record = map { $_->{'vhost_name'} => $_ } @$all_records;

    local $@;
    my $primary_vhosts_ro = eval { Cpanel::HttpUtils::Vhosts::PrimaryReader->new() };
    chomp $@         if $@;
    return ( 0, $@ ) if !$primary_vhosts_ro;

    my $record_rdr = Whostmgr::SSL::_Reader->new();

    my %vhost_aliases;

    my %user_proxy_labels;

    my $userowner_ref;

    my @sslvhosts;

    while ( my $rec = $record_rdr->get_record() ) {
        my ( $server, $domainowner, $type, $base_domain, $docroot, $ssl_ip, $ipv6 ) =
          @{$rec}[ DOMAIN, DOMAIN_OWNER, DOMAIN_TYPE, BASE_DOMAIN, DOCUMENT_ROOT, SSL_IP, IPV6 ];

        if ( $type eq 'parked' || $type eq 'addon' ) {
            if ( $OPTS{'aliases'} ) {
                my $labels = ( $user_proxy_labels{$domainowner} ||= [ Cpanel::WebVhosts::ProxySubdomains::ssl_proxy_subdomain_labels_for_user($domainowner) ] );

                # addon/parked domain has proxy subs, www, mail
                push @{ $vhost_aliases{$base_domain} }, $server, map { $_ . '.' . $server } ( ( $ipv6 ? 'ipv6' : () ), Cpanel::WebVhosts::AutoDomains::ON_ALL_CREATED_DOMAINS(), Cpanel::WebVhosts::AutoDomains::WEB_SUBDOMAINS_FOR_ZONE(), @$labels );
            }
            next;
        }

        # Only process vhosts that have an apache_tls entry.
        # This ensures that we only present vhosts with a user-manageable SSL cert,
        # and avoid displaying any "fallback" certs that are automatically set on the server.
        next unless $vhost_record{$server};

        substr( $ssl_ip, index( $ssl_ip, ':' ) ) = q<>;

        my $primary_ssl_servername_on_ip = $primary_vhosts_ro->get_primary_ssl_servername($ssl_ip);
        my $primary_cert_id              = $apache_tls_idx->get_for_vhost($primary_ssl_servername_on_ip);
        $primary_cert_id &&= $primary_cert_id->{'certificate_id'};

        if ( !$has_root && ( $domainowner ne $ENV{'REMOTE_USER'} ) ) {
            $userowner_ref ||= Cpanel::Config::LoadUserOwners::loadtrueuserowners( undef, 1, 1 );
            next if $userowner_ref->{$domainowner} ne $ENV{'REMOTE_USER'};
        }

        my %new_item = (
            'docroot'          => $docroot,
            'sslhost'          => $server,
            'is_primary_on_ip' => ( $primary_ssl_servername_on_ip && ( $server eq $primary_ssl_servername_on_ip ) ) ? 1 : 0,
            'user'             => $domainowner,
            'ip'               => $ssl_ip,
            'iptype'           => ( $sharedips{$ssl_ip} ? 'shared' : 'dedicated' ),
            'sharedip'         => ( $sharedips{$ssl_ip} ? 1        : 0 ),
            'hasssl'           => 1,
            'mail_sni_status'  => 1,

            'crt' => scalar _convert_apache_tls_index_record_to_api( $vhost_record{$server} ),

            #SNI is needed if the cert on the vhost is not the same
            #as the IP’s primary cert. (Even then it would be ok if
            #the primary cert covers the requested domain, but that’s
            #a bit unlikely.)
            'needs_sni' => $primary_cert_id && $primary_cert_id eq $vhost_record{$server}->{'id'} ? 0 : 1,
            'ipv6'      => $ipv6,
            'type'      => $type,
        );

        push @sslvhosts, \%new_item;
    }

    _augment_sslvhosts_with_aliases( \@sslvhosts, \%vhost_aliases, \%user_proxy_labels ) if $OPTS{'aliases'};

    return ( 1, \@sslvhosts );
}

sub _augment_sslvhosts_with_aliases {
    my ( $sslvhosts_ar, $vhost_aliases_hr, $user_proxy_labels_hr ) = @_;

    # No we add in all the aliases since we are sure we have processed
    # all the parked and addon domains once we reach the end of the Whostmgr:::SSL::_Reader object's
    # list.  It is important to do this at the end to ensure the %vhost_aliases hash
    # is fully populated before we add the aliases.
    foreach my $item_hr (@$sslvhosts_ar) {
        my ( $server, $type, $domainowner, $ipv6 ) = @{$item_hr}{ 'sslhost', 'type', 'user', 'ipv6' };
        $item_hr->{'aliases'} = $vhost_aliases_hr->{$server} ||= [];
        my $labels = ( $user_proxy_labels_hr->{$domainowner} ||= [ Cpanel::WebVhosts::ProxySubdomains::ssl_proxy_subdomain_labels_for_user($domainowner) ] );

        if ( $type eq 'main' ) {

            # main domain has proxy subs, www, mail
            push @{ $item_hr->{'aliases'} }, map { $_ . '.' . $server } ( ( $ipv6 ? 'ipv6' : () ), Cpanel::WebVhosts::AutoDomains::ON_ALL_CREATED_DOMAINS(), Cpanel::WebVhosts::AutoDomains::WEB_SUBDOMAINS_FOR_ZONE(), @$labels );
        }
        else {
            # subdomain only has www
            push @{ $item_hr->{'aliases'} }, "www.$server";
        }

        # In case they have proxy subdomain overwrites we need to
        # uniq the list
        @{ $item_hr->{'aliases'} } = Cpanel::ArrayFunc::Uniq::uniq( @{ $item_hr->{'aliases'} } );
    }
    return 1;
}

#When the old installed-SSLStorage was removed, the backend storage changed
#significantly. This mimics the data as that structure held it.
sub _convert_apache_tls_index_record_to_api {
    my ($crt) = @_;

    #On IPv6 servers we have the “same” vhost with both IPv4 and IPv6
    #IP addresses; we only convert each one once.
    if ( $crt->{'certificate_id'} ) {
        require Cpanel::Apache::TLS;
        $crt->{'id'} = delete $crt->{'certificate_id'};

        $crt->{'domains'} = delete $crt->{'certificate_domains'};

        my $vhname = delete $crt->{'vhost_name'};
        $crt->{'is_self_signed'} = $crt->{'subject'} eq $crt->{'issuer'};

        $crt->{'not_after'}  = Cpanel::Time::ISO::iso2unix( $crt->{'not_after'} );
        $crt->{'not_before'} = Cpanel::Time::ISO::iso2unix( $crt->{'not_before'} );

        #We don’t store this in the DB because the filesystem gives it to us.
        $crt->{'created'} = ( stat Cpanel::Apache::TLS->get_tls_path($vhname) )[10];

        $crt->{'subject_text'}       = _atls_dn_to_text( $crt->{'subject'} );
        $crt->{'subject.commonName'} = _atls_dn_to_hr( delete $crt->{'subject'} );

        $crt->{'issuer_text'} = _atls_dn_to_text( $crt->{'issuer'} );
        my $issuer_hr = _atls_dn_to_hr( delete $crt->{'issuer'} );
        $crt->{'issuer.commonName'}       = $issuer_hr->{'commonName'};
        $crt->{'issuer.organizationName'} = $issuer_hr->{'organizationName'};

        $_ //= undef for @{$crt}{
            'modulus',
            'modulus_length',
            'ecdsa_curve_name',
            'ecdsa_public',
        };
    }

    return $crt;
}

sub _atls_dn_to_text {
    my ($dn_txt) = @_;

    return join( "\n", map { split m<=>, $_, 2 } split m<\n>, $dn_txt );
}

sub _atls_dn_to_hr {
    my ($dn_txt) = @_;

    return { map { split m<=>, $_, 2 } split m<\n>, $dn_txt };
}

#%OPTS is:
#   servername (optional) - A specific servername to return.
sub fetch_vhost_ssl_components {
    my (%OPTS) = @_;

    my $search_servername = $OPTS{'servername'};

    require Cpanel::Apache::TLS;
    require Cpanel::SSLStorage::Utils;
    my @vhosts = Cpanel::Apache::TLS->get_tls_vhosts();

    my $total_ssl_count = 0;

    my @to_return;
    while ( my $servername = shift @vhosts ) {
        my $ok;

        if ( !Whostmgr::ACLS::hasroot() ) {
            my $domainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner($servername);
            next if ( $ENV{'REMOTE_USER'} ne $domainowner ) && !Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $domainowner );
        }

        $total_ssl_count++;

        if ( $search_servername && ( $servername ne $search_servername ) ) {
            next;
        }

        my ( $key, $crt, @cab ) = Cpanel::Apache::TLS->get_tls($servername);

        my $cab_pem = @cab ? join( "\n", @cab ) : undef;

        my %record = (
            servername  => $servername,
            certificate => $crt,
            key         => $key,
            cabundle    => $cab_pem,
        );

        ( $ok, my $crt_id ) = Cpanel::SSLStorage::Utils::make_certificate_id($crt);
        die $crt_id if !$ok;

        ( $ok, my $key_id ) = Cpanel::SSLStorage::Utils::make_key_id($key);
        die $key_id if !$ok;

        @record{ 'certificate_id', 'key_id' } = ( $crt_id, $key_id );

        if (@cab) {
            ( $ok, my $cab_id ) = Cpanel::SSLStorage::Utils::make_cabundle_id($cab_pem);
            die $cab_id if !$ok;

            $record{'cabundle_id'} = $cab_id;
        }
        else {
            $record{'cabundle_id'} = undef;
        }

        push @to_return, \%record;
    }

    return (
        1,
        {
            ssl_vhosts_count => $total_ssl_count,
            components       => \@to_return,
        }
    );
}

#Put this code into a module so we can (eventually) not have to reload the SSL install page
#after installing SSL.
sub fetch_ips_for_ssl_install {
    my %undedicated_ips;

    local $@;
    my $primary_vhosts_ro = eval { Cpanel::HttpUtils::Vhosts::PrimaryReader->new() };
    chomp $@         if $@;
    return ( 0, $@ ) if !$primary_vhosts_ro;

    require Cpanel::DIp;
    my $dedicated_ips_ref = Cpanel::DIp::Owner::get_all_dedicated_ips();
    my %sharedips         = Cpanel::DIp::get_all_shared_ips();

    my $ssl_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

  IP:
    foreach my $ip ( sort( Cpanel::IP::Configured::getconfiguredips() ) ) {
        next IP if $dedicated_ips_ref->{$ip};

        if ( !$undedicated_ips{ Cpanel::NAT::get_public_ip($ip) } ) {
            my $primary_servername = $primary_vhosts_ro->get_primary_ssl_servername($ip);
            my $primary_aliases;
            if ($primary_servername) {
                require Cpanel::Domain::Owner;

                my $username = Cpanel::Domain::Owner::get_owner_or_undef($primary_servername);
                $username ||= 'nobody';

                require Cpanel::Config::userdata::Load;

                my $vh_conf = Cpanel::Config::userdata::Load::load_ssl_domain_userdata( $username, $primary_servername );
                if ( !$vh_conf || !%$vh_conf ) {
                    Cpanel::Debug::log_warn("Web vhost “$primary_servername” (primary on $ip, owned by $username) lacks a vhost configuration file!");
                    next IP;
                }

                $primary_aliases = [ split m< >, $vh_conf->{'serveralias'} ];
            }

            $undedicated_ips{ Cpanel::NAT::get_public_ip($ip) } = {
                'ip'                     => Cpanel::NAT::get_public_ip($ip),
                'is_shared_ip'           => $sharedips{$ip} ? 1 : 0,
                'primary_ssl_servername' => $primary_servername,
                'primary_ssl_aliases'    => $primary_aliases,
            };
        }
    }

    return ( 1, \%undedicated_ips );
}

sub reseller_aware_fetch_sslinfo {
    my ( $domain, $crtdata ) = @_;

    my $allowed_users;
    if ( Whostmgr::ACLS::hasroot() ) {
        $allowed_users = undef;
    }
    else {
        $allowed_users = [ $ENV{'REMOTE_USER'} ];

        if ($domain) {
            require Cpanel::AcctUtils::DomainOwner::BAMP;
            if ( my $domain_owner = Cpanel::AcctUtils::DomainOwner::BAMP::getdomainownerBAMP( $domain, { 'default' => '' } ) ) {
                if ( $domain_owner && $ENV{'REMOTE_USER'} && Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $domain_owner ) ) {
                    $allowed_users = [ $ENV{'REMOTE_USER'}, $domain_owner ];
                }
            }
        }
    }

    require Cpanel::SSLInfo;

    # Fetch the information if possible
    return Cpanel::SSLInfo::fetchinfo( $domain, $crtdata, $allowed_users );
}

#----------------------------------------------------------------------
# This class abstracts away the reading of the main userdata cache and
# “nobody”’s userdata so that we get a consistent interface between them.
# It may be useful elsewhere.

package Whostmgr::SSL::_Reader;

use Cpanel::Config::userdata::Cache ();

use constant SSL_IP => 7;

sub new {
    my ( $class, @opts_kv ) = @_;

    my $fh = Cpanel::Config::userdata::Cache::open_cache() || do {
        die "Failed to open main vhost config cache after rebuild!";
    };

    return bless { _fh => $fh, @opts_kv }, $class;
}

sub get_record {
    my ($self) = @_;

    my $rec;

    if ( !$self->{'_fh_is_done'} ) {
        $rec = Cpanel::Config::userdata::Cache::read_cache( $self->{'_fh'} );

        # only return data where there is an ssl ip
        while ( $rec && !$rec->[SSL_IP] ) {
            $rec = Cpanel::Config::userdata::Cache::read_cache( $self->{'_fh'} );
        }

        $self->{'_fh_is_done'} = 1 if !$rec;
    }

    # The main userdata cache doesn’t contain “nobody”’s information.
    # The following logic creates mock records for “nobody” that can
    # be treated as though they came from the userdata cache.
    return $rec ||= do {
        close $self->{'_fh'};

        require Cpanel::Config::Httpd::IpPort;
        my $ssl_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

        require Cpanel::Config::WebVhosts;
        local $@;
        my $wvh = $self->{'_wvh'} ||= eval { Cpanel::Config::WebVhosts->load('nobody'); };

        if ($@) {
            Cpanel::Debug::log_warn($@);
        }

        if ($wvh) {
            $self->{'_nobody_records'} ||= do {
                my @records;

                for my $vh_name ( $wvh->main_domain(), $wvh->subdomains() ) {
                    require Cpanel::Config::userdata::Load;
                    my $vh_conf = Cpanel::Config::userdata::Load::load_ssl_domain_userdata( 'nobody', $vh_name );

                    next if !$vh_conf || !%$vh_conf;

                    my @rec;
                    @rec[ 0, 1, 3, 4, 5, 7 ] = (
                        $vh_name,
                        'nobody',
                        'sub',
                        $vh_name,
                        $vh_conf->{'documentroot'},
                        "$vh_conf->{'ip'}:$ssl_port",
                    );

                    push @records, \@rec;
                }

                \@records;
            };

            shift @{ $self->{'_nobody_records'} };
        }
    };
}

1;
