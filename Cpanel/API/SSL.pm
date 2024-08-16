
# cpanel - Cpanel/API/SSL.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::API::SSL;

use cPstrict;

use Cpanel                       ();
use Cpanel::AdminBin             ();
use Cpanel::AdminBin::Call       ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::ArrayFunc            ();
use Cpanel::ExpVar::Utils        ();
use Cpanel::Locale               ();
use Cpanel::Debug                ();
use Cpanel::NAT                  ();

our $INSTALLED_HOSTS_SSL_DB_FILE;

=encoding utf-8

=head1 NAME

Cpanel::API::SSL - UAPI functions to manage SSL certificates and keys.

=cut

our $VERSION = '1.5';
my ( $locale, $sslstorage );

my @subject_components = qw(
  countryName
  emailAddress
  localityName
  organizationName
  organizationalUnitName
  stateOrProvinceName
);

{
    my $init;

    sub _init {
        return if $init;

        # avoid to compile in shipped Cpanel::SSL* modules in cpanel.pl
        #   lazy load the modules at run time

        # use multiple lines for PPI parsing purpose
        require Cpanel::OpenSSL;             # PPI NO PARSE - loaded in _init();
        require Cpanel::SSL::Domain;         # PPI NO PARSE - loaded in _init();
        require Cpanel::SSL::ServiceMap;     # PPI NO PARSE - loaded in _init();
        require Cpanel::SSLInfo;             # PPI NO PARSE - loaded in _init();
        require Cpanel::SSLStorage::User;    # PPI NO PARSE - loaded in _init();
        require Cpanel::SSL::Utils;
        require Cpanel::Crypt::Algorithm;

        return 1;
    }
}

my $sslmanager_feature_allow_demo = {
    needs_role    => 'UserSSL',
    needs_feature => 'sslmanager',
    allow_demo    => 1,
};

my $sslmanager_feature_deny_demo = {
    needs_role    => 'UserSSL',
    needs_feature => 'sslmanager',
};

my $sslinstall_feature_allow_demo = {
    needs_role    => 'UserSSL',
    needs_feature => 'sslinstall',
    allow_demo    => 1
};

my $sslinstall_feature_deny_demo = {
    needs_role    => 'UserSSL',
    needs_feature => 'sslinstall'
};

my $autossl_sslinstall_features = {
    needs_role    => 'UserSSL',
    needs_feature => { match => 'all', features => [qw(autossl sslinstall)] },
    allow_demo    => 1,
};

my $allow_demo = { allow_demo => 1 };

our %API = (
    list_keys                              => $sslmanager_feature_allow_demo,
    show_key                               => $sslmanager_feature_allow_demo,
    generate_key                           => $sslmanager_feature_deny_demo,
    upload_key                             => $sslmanager_feature_deny_demo,
    set_key_friendly_name                  => $sslmanager_feature_deny_demo,
    delete_key                             => $sslmanager_feature_deny_demo,
    find_certificates_for_key              => $allow_demo,
    find_csrs_for_key                      => $allow_demo,
    list_csrs                              => $sslmanager_feature_allow_demo,
    show_csr                               => $sslmanager_feature_allow_demo,
    generate_csr                           => $sslmanager_feature_deny_demo,
    set_csr_friendly_name                  => $sslmanager_feature_deny_demo,
    delete_csr                             => $sslmanager_feature_deny_demo,
    list_certs                             => $sslmanager_feature_allow_demo,
    fetch_cert_info                        => $sslmanager_feature_allow_demo,
    show_cert                              => $sslmanager_feature_allow_demo,
    generate_cert                          => $sslmanager_feature_deny_demo,
    upload_cert                            => $sslmanager_feature_deny_demo,
    set_cert_friendly_name                 => $sslmanager_feature_deny_demo,
    delete_cert                            => $sslmanager_feature_deny_demo,
    get_cabundle                           => $sslinstall_feature_allow_demo,
    fetch_certificates_for_fqdns           => $allow_demo,
    fetch_best_for_domain                  => $allow_demo,
    fetch_key_and_cabundle_for_certificate => $allow_demo,
    rebuildssldb                           => $allow_demo,
    list_ssl_items                         => $sslmanager_feature_allow_demo,
    enable_mail_sni                        => $sslinstall_feature_deny_demo,
    disable_mail_sni                       => $allow_demo,
    mail_sni_status                        => $allow_demo,
    rebuild_mail_sni_config                => $sslinstall_feature_allow_demo,
    set_primary_ssl                        => $sslinstall_feature_deny_demo,
    install_ssl                            => $sslinstall_feature_deny_demo,
    delete_ssl                             => $sslinstall_feature_deny_demo,
    installed_host                         => $sslinstall_feature_allow_demo,
    installed_hosts                        => $sslinstall_feature_allow_demo,
    is_sni_supported                       => $sslinstall_feature_allow_demo,
    is_mail_sni_supported                  => $sslinstall_feature_allow_demo,
    get_cn_name                            => $allow_demo,
    get_autossl_excluded_domains           => { needs_role => "UserSSL", needs_feature => "autossl" },
    set_autossl_excluded_domains           => $autossl_sslinstall_features,
    add_autossl_excluded_domains           => $autossl_sslinstall_features,
    remove_autossl_excluded_domains        => $autossl_sslinstall_features,
    start_autossl_check                    => $autossl_sslinstall_features,
    is_autossl_check_in_progress           => $autossl_sslinstall_features,
    get_autossl_problems                   => $autossl_sslinstall_features,
    get_autossl_pending_queue              => $autossl_sslinstall_features,
    can_ssl_redirect                       => $allow_demo,
    toggle_ssl_redirect_for_domains        => $allow_demo,

    set_default_key_type => $sslmanager_feature_allow_demo,
);

=head1 Methods

=over 8

=cut

sub set_default_key_type ( $args, $result, @ ) {
    require Cpanel::SSL::DefaultKey::Constants;

    my $value = $args->get_length_required('type');

    if ( $value ne Cpanel::SSL::DefaultKey::Constants::USER_SYSTEM() ) {
        require Cpanel::SSL::DefaultKey;
        if ( !Cpanel::SSL::DefaultKey::is_valid_value($value) ) {
            my $locale = Cpanel::Locale->get_handle();
            $result->raw_error( $locale->maketext( '“[_1]” is not a valid “[_2]”.', $value, 'type' ) );
            return 0;
        }
    }

    require Cpanel::AdminBin::Call;
    require Cpanel::Config::CpUser::WriteAsUser;

    Cpanel::Config::CpUser::WriteAsUser::write(
        SSL_DEFAULT_KEY_TYPE => $value,
    );

    Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'START_AUTOSSL_CHECK' );

    return 1;
}

##################################################
## cpdev: KEYS

sub list_keys {
    my ( $args, $result ) = @_;

    _init();

    if ( !$sslstorage ) {
        my $ok;
        ( $ok, $sslstorage ) = Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();

        if ( !$ok ) {
            $result->raw_error($sslstorage);
            return;
        }
    }

    my ( $ok, $keys ) = $sslstorage->find_keys();
    if ( !$ok ) {
        $result->raw_error($keys);
        return;
    }

    $result->data($keys);
    return 1;
}

sub show_key {
    my ( $args, $result ) = @_;

    _init();

    $sslstorage = eval { Cpanel::SSLStorage::User->new() };    # PPI NO PARSE - loaded in _init();

    if ($@) {
        $result->raw_error($@);
        return;
    }

    my @search_args = _get_search_args( $args, $result ) or return;
    my $ok;
    my $keys;

    ( $ok, $keys ) = $sslstorage->find_keys(@search_args);
    if ( !$ok ) {
        $result->raw_error($keys);
        return;
    }

    if ( !@$keys ) {
        $result->error('No key matches that search term.');
        return;
    }

    my $key;
    my $id = $keys->[0]{'id'};
    ( $ok, $key ) = $sslstorage->get_key_text($id);
    if ( !$ok ) {
        $result->error( 'An error occurred while retrieving the key with ID “[_1]”: [_2]', $id, $key );
        return;
    }

    my $openssl = Cpanel::OpenSSL->new();    # PPI NO PARSE - loaded in _init();
    if ( !$openssl ) {
        $result->error('There is a problem with the system OpenSSL installation.');
        return;
    }

    my $ssl_result = $openssl->get_key_text( { 'stdin' => $key } );
    if ( !$ssl_result->{'status'} ) {
        $result->error( 'An error occurred while parsing the key with ID “[_1]”: [_2]', $id, $ssl_result->{'message'} );
        return;
    }

    my %data = ( key => $key, text => $ssl_result->{'text'}, details => $keys->[0] );
    $result->data( \%data );
    return 1;
}

#NOTE: Do NOT document the _api2_legacy_rename_old_friendly_name_never_use_this flag!
#It's there for compatibility with API2.
sub generate_key {
    my ( $args, $result ) = @_;
    my ( $keysize, $keytype, $friendly_name, $rename_old_fn ) = $args->get(qw(keysize  keytype  friendly_name  _api2_legacy_rename_old_friendly_name_never_use_this ));

    ## note: inlined code of ::SSL::_genkey
    _init();

    if ($keysize) {
        if ( $keysize !~ m/^\d+$/ || $keysize < $Cpanel::OpenSSL::DEFAULT_KEY_SIZE || $keysize > 4096 ) {    # PPI NO PARSE - loaded in _init();

            $result->error( '“[_1]” must be an integer value between “[_2]” and “[_3]” (inclusive).', 'keysize', $Cpanel::OpenSSL::DEFAULT_KEY_SIZE, 4096 );    # PPI NO PARSE - loaded in _init();
            return;
        }
    }

    require Cpanel::SSL::Legacy;
    my $key_pem = Cpanel::SSL::Legacy::generate_key_from_keysize_and_keytype(
        $Cpanel::user,
        $keysize, $keytype,
    );

    my $rec = _save_key(
        $result, $key_pem,
        {
            friendly_name => $friendly_name,
            rename_old_fn => $rename_old_fn,
        }
    ) or return;

    $result->data( { %$rec, text => $key_pem } );

    return 1;
}

#NOTE: Do NOT document the _api2_legacy_rename_old_friendly_name_never_use_this flag!
#It's there for compatibility with API2.
sub upload_key ( $args, $result ) {

    ## $args contains 'key' and 'domain', but might also contain a pair of unknown keys
    ##   that signify an upload filepath (e.g. "file-${fname}" and "file-${fname}-key")

    my ( $key_from_form, $friendly_name, $rename_old_fn ) = $args->get(qw(key  friendly_name  _api2_legacy_rename_old_friendly_name_never_use_this));

    _init();

    local $Cpanel::IxHash::Modify = 'none';    # PPI NO PARSE - only needed if loaded

    my $key_from_file;

    my $uploaded_files = $args->get_uploaded_files();

    foreach my $file ( sort keys $uploaded_files->%* ) {
        my $file_path = $uploaded_files->{$file}->{tmp_filepath};
        next unless -e $file_path;
        if ( open my $key_fh, '<', $file_path ) {
            while ( my $line = readline $key_fh ) {
                $key_from_file .= $line;
            }
            close $key_fh;
            unlink $file_path;
            last;
        }
        else {
            Cpanel::Debug::log_warn("Unable to read $file_path: $!");
        }
    }

    my @keys_to_save;
    if ($key_from_file) { push @keys_to_save, $key_from_file; }
    if ($key_from_form) { push @keys_to_save, $key_from_form; }

    my $openssl = Cpanel::OpenSSL->new();    # PPI NO PARSE - loaded in _init();
    if ( !$openssl ) {
        $result->error('There is a problem with the system OpenSSL installation.');
        return;
    }

    if ( !@keys_to_save ) {
        $result->error('You did not provide a key to be installed.');
        return;
    }

    #First we ensure that all keys to be saved are valid.
    foreach my $key (@keys_to_save) {
        $key = Cpanel::SSLInfo::demunge_ssldata($key);    # PPI NO PARSE - loaded in _init();
        if ($key) {
            my ( $ok, $why ) = Cpanel::SSL::Utils::parse_key_text($key);

            if ( !$ok ) {
                $result->error("Invalid key submitted ($why)");
                return 0;
            }
        }
        else {
            Cpanel::Debug::log_warn('Invalid key encountered');
            $result->error('The key could not be processed. Please make sure it is in the correct format.');
            return;
        }
    }

    #Now actually write out the keys. Bail out at the first sign of trouble.
    my @records_written;
    for my $key (@keys_to_save) {
        my $rec = _save_key(
            $result, $key,
            {
                friendly_name => $friendly_name,
                rename_old_fn => $rename_old_fn,
            }
        ) or return;
        push @records_written, $rec;
    }

    $result->data( \@records_written );

    return 1;
}

sub set_key_friendly_name {
    my ( $args, $result ) = @_;

    return _set_friendly_name( $args, $result, 'key' );
}

sub delete_key {
    my ( $args, $result ) = @_;

    return _delete( $args, $result, 'key' );
}

sub find_certificates_for_key {
    my ( $args, $result ) = @_;

    my @search_terms = _find_matching_key_search_terms( $args, $result ) or return;

    my ( $ok, $certs ) = $sslstorage->find_certificates(@search_terms);
    if ( !$ok ) {
        $result->raw_error($certs);
        return;
    }

    $result->data($certs);
    return 1;
}

sub find_csrs_for_key {
    my ( $args, $result ) = @_;

    my @search_terms = _find_matching_key_search_terms( $args, $result ) or return;

    my ( $ok, $csrs ) = $sslstorage->find_csrs(@search_terms);
    if ( !$ok ) {
        $result->raw_error($csrs);
        return;
    }

    $result->data($csrs);
    return 1;
}

##################################################
## cpdev: CSRS

sub list_csrs {
    my ( $args, $result ) = @_;

    _init();

    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();

    my ( $ok, $csrs ) = $sslstorage->find_csrs();
    if ( !$ok ) {
        $result->raw_error($csrs);
        return;
    }

    $result->data($csrs);
    return 1;
}

#Give either id or friendly_name
sub show_csr {
    my ( $args, $result ) = @_;

    _init();

    my @search_args = _get_search_args( $args, $result ) or return;

    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();

    my ( $ok, $csrs ) = $sslstorage->find_csrs(@search_args);
    if ( !$ok ) {
        $result->raw_error($csrs);
        return;
    }

    if ( !@$csrs ) {
        $result->error('No certificate signing request matches that search term.');
        return;
    }

    my $id = $csrs->[0]{'id'};

    my $csr;
    ( $ok, $csr ) = $sslstorage->get_csr_text($id);
    if ( !$ok ) {
        $result->raw_error($csr);
        return;
    }

    ( $ok, my $parse ) = Cpanel::SSL::Utils::parse_csr_text($csr);    # PPI NO PARSE - loaded in _init();
    if ( !$ok ) {
        $result->raw_error($parse);
        return;
    }

    # Build the CSR record
    my $details = {
        'id' => $id,

        'created'                => $csrs->[0]->{'created'},
        'commonName'             => $parse->{'commonName'},
        'localityName'           => $parse->{'localityName'},
        'stateOrProvinceName'    => $parse->{'stateOrProvinceName'},
        'countryName'            => $parse->{'countryName'},
        'organizationName'       => $parse->{'organizationName'},
        'organizationalUnitName' => $parse->{'organizationalUnitName'},
        'emailAddress'           => $parse->{'emailAddress'},
        'friendly_name'          => $csrs->[0]{'friendly_name'},
        'domains'                => $parse->{'domains'},

        map { $_ => $parse->$_() } (
            'modulus',
            'ecdsa_curve_name',
            'ecdsa_public',
            'key_algorithm',
        ),
    };

    my $openssl = _get_openssl($result) or return;

    my $ssl_result = $openssl->get_csr_text( { 'stdin' => $csr } );
    my %data       = ( csr => $csr, text => $ssl_result->{'text'}, details => $details );
    $result->data( \%data );
    return 1;
}

sub generate_csr {
    my ( $args, $result ) = @_;

    _init();

    ## note: inlined code of ::SSL::_gencsr
    my ( $key_id, $pass, $friendly_name, $domains, $rename_old_fn ) = $args->get(qw(key_id  pass  friendly_name  domains  _api2_legacy_rename_old_friendly_name_never_use_this));

    for my $req (qw(key_id domains)) {
        if ( !length $args->get($req) ) {
            $result->error( 'You must specify the “[_1]”.', $req );
            return;
        }
    }

    $domains =~ s{\A\s+|\s+\z}{}g;
    $domains = [ split m{[,;\s]+}, $domains ];

    require Cpanel::Validate::Domain;
    for my $dom (@$domains) {
        if ( !Cpanel::Validate::Domain::valid_wild_domainname($dom) ) {
            $result->error( '“[_1]” is not a valid domain.', $dom );
            return;
        }
    }

    my %subject;
    @subject{@subject_components} = $args->get(@subject_components);

    my $openssl = Cpanel::OpenSSL->new();    # PPI NO PARSE - loaded in _init();
    unless ($openssl) {
        $result->error('There is a problem with the system OpenSSL installation.');
        return;
    }

    my ( $sslok, $sslresult ) = _checkssldata( 'type' => 'csr', 'pass' => $pass, %subject );
    unless ($sslok) {
        $result->error( 'Sorry, the value of [_1] was not valid, or too short', $sslresult );
        return;
    }

    #Can't do ||= here in case the last $sslstorage wasn't renaming old friendly_name
    my $sslstorage = Cpanel::SSLStorage::User->new( 'rename_old_friendly_name' => $rename_old_fn );    # PPI NO PARSE - loaded in _init();

    my ( $ok, $key ) = $sslstorage->get_key_text($key_id);
    if ( !$ok ) {
        $result->error( 'An error occurred while retrieving the key with ID “[_1]”: [_2]', $key_id, $key );
        return;
    }

    require Cpanel::TempFile;
    my $temp_file = Cpanel::TempFile->new();
    my ( $keyfile, $key_fh ) = $temp_file->file();
    print {$key_fh} $key;
    close $key_fh;

    my $gen_result = $openssl->generate_csr(
        {
            'keyfile'  => $keyfile,
            'domains'  => $domains,
            'password' => $pass,
            %subject,
        }
    );

    unless ( $gen_result->{'status'} ) {
        $result->error( 'Failed to generate Certificate Signing Request: [_1]', $gen_result->{'stderr'} || $gen_result->{'message'} );
        return;
    }

    my $record;
    ( $ok, $record ) = $sslstorage->add_csr( text => $gen_result->{'stdout'}, friendly_name => $friendly_name );
    if ( !$ok ) {
        $result->raw_error($record);
        return;
    }

    $result->data( { %$record, text => $gen_result->{'stdout'} } );

    $result->message('Certificate Signing Request generated!');
    return 1;
}

sub set_csr_friendly_name {
    my ( $args, $result ) = @_;

    return _set_friendly_name( $args, $result, 'csr' );
}

sub delete_csr {
    my ( $args, $result ) = @_;

    return _delete( $args, $result, 'csr' );
}

##################################################
## cpdev: CERTS

sub list_certs {
    my ( $args, $result ) = @_;

    _init();

    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();
    my ( $ok, $certs ) = $sslstorage->find_certificates();
    if ( !$ok ) {
        $result->raw_error($certs);
        return;
    }

    _decorate_sslstorage_certs_for_list_certs($certs);

    $result->data($certs);
    return 1;
}

sub _decorate_sslstorage_certs_for_list_certs {
    my ($certs_ar) = @_;

    require Cpanel::WebVhosts;
    my @all_installable_domains = map { $_->{'domain'} } Cpanel::WebVhosts::list_ssl_capable_domains($Cpanel::user);

    for my $cert (@$certs_ar) {
        $cert->{'domain_is_configured'} = Cpanel::SSL::Utils::validate_domains_lists_have_match( $cert->{'domains'}, \@all_installable_domains ) ? 1 : 0;    # PPI NO PARSE - loaded in _init();
    }

    return;
}

sub fetch_cert_info {
    my ( $args, $result ) = @_;

    _init();

    my @search_args = _get_search_args( $args, $result ) or return;

    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();

    my ( $ok, $crts ) = $sslstorage->find_certificates(@search_args);
    if ( !$ok ) {
        $result->raw_error($crts);
        return;
    }

    if ( !@$crts ) {
        $result->error('No certificate matches that search term.');
        return;
    }

    my $id = $crts->[0]{'id'};

    my $payload;
    ( $ok, $payload ) = Cpanel::SSLInfo::fetch_crt_info($id);    # PPI NO PARSE - loaded in _init();
    if ( !$ok ) {
        $result->raw_error($payload);
        return;
    }

    $result->data($payload);
    return 1;
}

sub show_cert {
    my ( $args, $result ) = @_;

    _init();

    my @search_args = _get_search_args( $args, $result ) or return;

    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();

    my ( $ok, $crts ) = $sslstorage->find_certificates(@search_args);
    if ( !$ok ) {
        $result->raw_error($crts);
        return;
    }

    if ( !@$crts ) {
        $result->error('No certificate matches that search term.');
        return;
    }

    my $id = $crts->[0]{'id'};
    my $text;
    ( $ok, $text ) = $sslstorage->get_certificate_text($id);
    if ( !$ok ) {
        $result->raw_error($text);
        return;
    }

    ( $ok, my $parse ) = Cpanel::SSL::Utils::parse_certificate_text($text);    # PPI NO PARSE - loaded in _init();
    if ( !$ok ) {
        $result->raw_error($parse);
        return;
    }

    # Build the certificate record
    my $details = {

        'id'            => $id,
        'friendly_name' => $crts->[0]{'friendly_name'},
        'domains'       => $crts->[0]{'domains'},

        map { $_ => $parse->$_() } (
            'key_algorithm',
            'modulus',
            'ecdsa_curve_name',
            'ecdsa_public',

            'not_before',
            'not_after',

            'subject',
            'issuer',

            'is_self_signed',
        ),
    };

    my $openssl = _get_openssl($result) or return;

    my $ssl_result = $openssl->get_cert_text( { 'stdin' => $text } );
    my %data       = ( cert => $text, text => $ssl_result->{'text'}, details => $details );
    $result->data( \%data );
    return 1;
}

#"domains" is joined with spaces
sub generate_cert {
    my ( $args, $result ) = @_;

    _init();

    my ( $key_id, $friendly_name, $domains, $rename_old_fn ) = $args->get(qw(key_id friendly_name domains _api2_legacy_rename_old_friendly_name_never_use_this));

    for my $req (qw(key_id domains)) {
        if ( !length $args->get($req) ) {
            $result->error( 'You must specify the “[_1]”.', $req );
            return;
        }
    }

    $domains =~ s{\A\s+|\s+\z}{}g;
    $domains = [ split m{[,;\s]+}, $domains ];

    require Cpanel::Validate::Domain;
    for my $dom (@$domains) {
        if ( !Cpanel::Validate::Domain::valid_wild_domainname($dom) ) {
            $result->error( '“[_1]” is not a valid domain.', $dom );
            return;
        }
    }

    my %subject;
    @subject{@subject_components} = $args->get(@subject_components);

    my ( $sslok, $sslresult ) = _checkssldata( 'type' => 'crt', %subject );
    unless ($sslok) {
        $result->error( 'Sorry, the value of [_1] was not valid, or too short', $sslresult );
        return;
    }

    #Can't do ||= here in case the last $sslstorage wasn't renaming old friendly_name
    my $sslstorage = Cpanel::SSLStorage::User->new( rename_old_friendly_name => $rename_old_fn );    # PPI NO PARSE - loaded in _init();

    my ( $ok, $key ) = $sslstorage->get_key_text($key_id);
    if ( !$ok ) {
        $result->error( 'An error occurred while retrieving the key with ID “[_1]”: [_2]', $key_id, $key );
        return;
    }

    my $openssl = Cpanel::OpenSSL->new();                                                            # PPI NO PARSE - loaded in _init();
    unless ($openssl) {
        $result->error('There is a problem with the system OpenSSL installation.');
        return;
    }

    require Cpanel::TempFile;
    my $temp_file = Cpanel::TempFile->new();
    my ( $keyfile, $key_fh ) = $temp_file->file();
    print {$key_fh} $key;
    close $key_fh;

    my $ssl_res = $openssl->generate_cert(
        {
            'keyfile' => $keyfile,
            'domains' => $domains,
            %subject,
        }
    );

    if ( $ssl_res->{'status'} ) {
        ( $ok, my $record ) = $sslstorage->add_certificate( text => $ssl_res->{'stdout'}, friendly_name => $friendly_name );
        if ( !$ok ) {
            $result->raw_error($record);
            return;
        }

        $result->data( { %$record, text => $ssl_res->{'stdout'} } );

        $result->message('Certificate generated!');

        return 1;
    }

    $result->raw_error( $ssl_res->{'stderr'} || $ssl_res->{'message'} );
    return;
}

# This routine will accept certificate text or the
# path to a certificate file on the system
sub upload_cert {
    my ( $args, $result ) = @_;
    ## $args contains 'crt', but might also contain a pair of unknown keys
    ##   that signify an upload filepath (e.g. "file-${fname}" and "file-${fname}-key")
    ## easiest to pass $args straight through to the utility function

    _init();

    my ( $crt_from_form, $friendly_name, $rename_old_fn ) = $args->get(qw(crt  friendly_name  _api2_legacy_rename_old_friendly_name_never_use_this));

    # Prevent munging of FORM items (passed by reference)
    local $Cpanel::IxHash::Modify = 'none';    # PPI NO PARSE - only set if loaded

    my $crt_from_file;
  FORMFILE:
    foreach my $key ( sort $args->keys() ) {
        if ( $key =~ m/^file-.+/ ) {
            my $file_path = $args->get($key);
            $file_path =~ s/\n//g;
            if ( -e $file_path ) {
                if ( open my $crt_fh, '<', $file_path ) {
                    while ( my $line = readline $crt_fh ) {
                        $crt_from_file .= $line;
                    }
                    close $crt_fh;
                    unlink $file_path;
                    last FORMFILE;
                }
                else {
                    Cpanel::Debug::log_warn("Unable to read $file_path: $!");
                }
            }
            else {
                Cpanel::Debug::log_warn("Certificate file $file_path does not exist");
            }
        }
    }

    my @certificates_to_save;
    if ($crt_from_file) { push @certificates_to_save, $crt_from_file; }
    if ($crt_from_form) { push @certificates_to_save, $crt_from_form; }

    if ( !@certificates_to_save ) {
        $result->error('You did not provide a certificate to be installed.');
        return;
    }

    my $cert_written;
    my $openssl = Cpanel::OpenSSL->new();    # PPI NO PARSE - loaded in _init()
    if ( !$openssl ) {
        $result->error('There is a problem with the system OpenSSL installation.');
        return;
    }

    #Can't do ||= here in case the last $sslstorage wasn't renaming old friendly_name
    my $sslstorage = Cpanel::SSLStorage::User->new( 'rename_old_friendly_name' => $rename_old_fn );    # PPI NO PARSE - loaded in _init();

    my @saved;

    my $crt_count = 0;

  CERTSAVE:
    foreach my $crt (@certificates_to_save) {
        $crt_count++;
        $crt = Cpanel::SSLInfo::demunge_ssldata($crt);    # PPI NO PARSE - loaded in _init();
        if ( !$crt ) {
            Cpanel::Debug::log_warn('Invalid certificate encountered');
            next CERTSAVE;
        }

        my ( $ok, $record ) = $sslstorage->add_certificate( text => $crt, friendly_name => $friendly_name );
        if ($ok) {
            $cert_written++;
            push @saved, $record;
        }
        else {
            my $locale = Cpanel::Locale->get_handle();
            my $error  = $locale->maketext( 'The system could not save certificate #[numf,_1] because of an error: [_2]', $crt_count, $record );
            Cpanel::Debug::log_warn($error);
            $result->raw_error($error);
            next CERTSAVE;
        }
    }
    if ( !$cert_written ) {
        $result->error('No valid certificate provided');
        return;
    }

    $result->data( \@saved );

    return 1;
}

sub set_cert_friendly_name {
    my ( $args, $result ) = @_;

    return _set_friendly_name( $args, $result, 'certificate' );
}

sub delete_cert {
    my ( $args, $result ) = @_;

    return _delete( $args, $result, 'certificate' );
}

##################################################
## cpdev: CABUNDLES

sub get_cabundle {
    my ( $args, $result ) = @_;
    my ($cert) = $args->get('cert');

    _init();

    my ( $domain, $bundle, $cab ) = Cpanel::SSLInfo::fetchcabundle($cert);    # PPI NO PARSE - loaded in _init();
    $result->data( { 'domain' => $domain, 'bundle' => $bundle, 'cab' => $cab } );
    return 1;
}

##################################################
## cpdev: MISCELLANEOUS

sub fetch_certificates_for_fqdns {
    my ( $args, $result ) = @_;

    _init();

    my @req_domains = split m<[,;\s]+>, $args->get_length_required('domains');

    require Cpanel::SSL::Search;

    my @certs_return = Cpanel::SSL::Search::fetch_users_certificates_for_fqdns(
        users   => [$Cpanel::user],
        domains => \@req_domains,
    );

    for my $c (@certs_return) {

        #throw away “users” since it’s redundant when running as the user
        @{$c}{ 'crt', 'cab' } = delete @{$c}{ 'certificate', 'ca_bundle', 'users' };
    }

    _decorate_sslstorage_certs_for_list_certs( \@certs_return );

    $result->data( \@certs_return );

    return 1;
}

sub _fetchinfo_wrapper {
    my ( $args, $result, $to_find ) = @_;

    my $to_find_value = $args->get($to_find);
    if ( !length $to_find_value ) {
        $result->error( 'You must specify the “[_1]”.', $to_find );
        return;
    }

    _init();
    my %params = ( $to_find => $to_find_value );

    #Either domain or certificate will be undef.
    my $fetch = Cpanel::SSLInfo::fetchinfo( @params{ 'domain', 'certificate' } );    # PPI NO PARSE - loaded in _init();
    if ( !$fetch->{'status'} ) {
        $result->raw_error( $fetch->{'statusmsg'} );
        return;
    }

    #Finding that there is no matching cert is NOT an error.
    if ( !$fetch->{'crt'} && $fetch->{'statusmsg'} ) {
        $result->raw_message( $fetch->{'statusmsg'} );
    }

    $result->data($fetch);
    return 1;
}

#Fetches the best cert for a domain along with key and CAB
#Returns a single hashref.
sub fetch_best_for_domain {
    my ( $args, $result ) = @_;

    return _fetchinfo_wrapper( $args, $result, 'domain' );
}

sub fetch_key_and_cabundle_for_certificate {
    my ( $args, $result ) = @_;

    return _fetchinfo_wrapper( $args, $result, 'certificate' );
}

#No arguments.
#Returns a list of:
#   { type:"key"/"certificate"/"csr", action:"add"/"remove", details:{...} }
#...where "details" is the return from list_*
sub rebuildssldb {
    my ( $args, $result ) = @_;

    _init();
    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();
    my ( $ok, $repair_ar ) = $sslstorage->rebuild_records();

    if ($ok) {
        $result->data($repair_ar);
    }
    else {
        $result->raw_error($repair_ar);
    }

    return $ok ? 1 : 0;
}

## 'domains' and 'items' are pipe-delimited strings
## not clear if this is used by anything other than SSL's listsslitems (which
##   does not seem to be called from x3/)
sub list_ssl_items {
    my ( $args,        $result )    = @_;
    my ( $domains_str, $items_str ) = $args->get( 'domains', 'items' );
    my @DOMAINS = defined $domains_str ? split( /\|/, $domains_str ) : ();
    my @ITEMS   = defined $items_str   ? split( /\|/, $items_str )   : ();

    _init();

    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();

    my @RSD;
    foreach my $item (@ITEMS) {
        my ( $status, $return_ref, $domain_related_key );
        if ( $item eq 'key' ) {

            # This is a special case since keys are no longer named for a domain upon creation
            # We will need to iterate through the list of domains requested and see if there are
            # keys associated with those domains and return those.
            for my $domain (@DOMAINS) {
                ( $status, $return_ref ) = $sslstorage->find_key_for_domain($domain);
                if ( !$status ) {
                    $result->raw_error($return_ref);
                    return;
                }

                if ($return_ref) {
                    push( @RSD, { 'type' => $item, 'host' => $domain, 'id' => $return_ref->{'id'} } );
                }
            }

            # the processing after this block is for csrs and crts, not keys - skipping since we've already processed the data
            next;
        }
        elsif ( $item eq 'csr' ) {
            ( $status, $return_ref ) = $sslstorage->find_csrs();
            if ( !$status ) {
                $result->raw_error($return_ref);
                return;
            }

            $domain_related_key = 'commonName';
        }
        elsif ( $item eq 'crt' ) {
            ( $status, $return_ref ) = $sslstorage->find_certificates();
            if ( !$status ) {
                $result->raw_error($return_ref);
                return;
            }

            $domain_related_key = 'subject.commonName';
        }
        else {
            next;
        }

        foreach my $ssl_info ( @{$return_ref} ) {
            my $domain = $ssl_info->{$domain_related_key};
            if ( grep( /^\Q$domain\E$/, @DOMAINS ) ) {
                push( @RSD, { 'type' => $item, 'host' => $domain, 'id' => $ssl_info->{'id'} } );
            }
        }
    }
    $result->data( \@RSD );
    return 1;
}

=item B<enable_mail_sni>

B<NOTE>: All domains now have mail SNI enabled automatically, so there is no
reason to use this function in new code.

Enables SNI for mail services on the specified domains.

B<Input>:

    'domains' => pipe-delimited string containing the list of domains to alter.
                 Example: 'cptest1.tld|cptest2.tld|cptest3.tld'.

B<Output>:

    {
        'updated_domains' => {
            'cptest2.tld' => 1,
            'cptest3.tld' => 1,
        }
    }

=cut

sub enable_mail_sni {
    my ( $args, $result ) = @_;
    my ($domains_str) = $args->get('domains');
    my @DOMAINS = defined $domains_str ? split( /\|/, $domains_str ) : ();

    if ( !scalar @DOMAINS ) {
        $result->error( 'You must specify “[_1]”.', 'domains' );
        return 0;
    }

    ## note: legacy use of CPERROR within &adminrun
    local $Cpanel::context = 'ssl';
    local $Cpanel::CPERROR{$Cpanel::context};

    #We preserve this adminbin call so that anything out there that may have
    #depended on this API to tell them about authz or domain existence will
    #continue to work.
    my $ret = Cpanel::AdminBin::fetch_adminbin_nocache_with_status( 'ssl', undef, 'SETSNISTATUS', 'storable', { 'domains' => \@DOMAINS, 'enable' => 1 } );
    if ( !$ret->{'status'} ) {
        $result->error( 'The system failed to enable SNI for Mail services on “[_1]” because of an error: [_2]', $domains_str, $ret->{'error'} );
        return;
    }

    $result->data( $ret->{data} );
    $result->message('cPanel & WHM always enables mail SNI from now on.');

    return 1;
}

=item B<disable_mail_sni>

This API call now always fails.

=cut

sub disable_mail_sni {

    die 'cPanel & WHM always enables mail SNI from now on.';
}

=item B<mail_sni_status>

Returns a hashref detailing whether or not SNI for mail services is enabled for the specified domain.

B<Input>: the domain to check

        'domain' => 'cptest.tld',

B<Output>:

    {
        'enabled' => 1 (or 0),
    }

=cut

sub mail_sni_status {
    my ( $args, $result ) = @_;
    my ($vhost_name) = $args->get('domain');

    if ( !length $vhost_name ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'domain' ] );
    }

    require Cpanel::MailUtils::SNI;

    #Will die() if the user controls no vhost with this name.
    Cpanel::MailUtils::SNI::sni_status($vhost_name);

    $result->data( { enabled => 1 } );
    $result->message('cPanel & WHM always enables mail SNI from now on.');

    return 1;
}

=item B<rebuild_mail_sni_config>

Rebuilds the SNI configuration files. This call should be made any time changes have been made to the SNI
status via the L<enable_mail_sni> or L<disable_mail_sni> calls.
B<NOTE>: As of v11.60, neither of those calls does anything, so there’s
less reason to call this.

B<Input>: An optional argument can be passed to 'reload' the Dovecot service once the configuration files
have been rebuilt:

    {
        'reload_dovecot' => 1,
    }

B<Output>: Returns a success value indicating whether or not the operation was successful:

    {
        'success' => 1
    }

=cut

sub rebuild_mail_sni_config {
    my ( $args, $result ) = @_;

    my ($reload_dovecot) = $args->get('reload_dovecot') || 0;

    ## note: legacy use of CPERROR within &adminrun
    local $Cpanel::context = 'ssl';
    local $Cpanel::CPERROR{$Cpanel::context};
    my $ret = Cpanel::AdminBin::fetch_adminbin_nocache_with_status( 'ssl', undef, 'REBUILDMAILSNICONFIG', 'storable', { 'reload_dovecot' => $reload_dovecot } );
    if ( !$ret->{'status'} ) {
        $result->error( 'The system failed to rebuild the mail SNI configuration on the server because of an error: [_1]', $ret->{'error'} );
        return;
    }

    $result->data( $ret->{'data'} ) if $ret->{'data'};
    return 1;
}

sub set_primary_ssl {
    my ( $args, $result ) = @_;

    if ( !Cpanel::ExpVar::Utils::hasdedicatedip() ) {
        $result->error( 'Your IP address ([_1]) is shared with other users. You cannot set a primary website unless you have a dedicated IP address.', $Cpanel::CPDATA{'IP'} );
        return;
    }

    my ($servername) = $args->get('servername');
    $servername =~ s{\A\s+|\s+\z}{} if $servername;
    if ( !$servername ) {
        $result->error( 'You must specify the “[_1]”.', 'servername' );
        return 0;
    }

    ## note: legacy use of CPERROR within &adminrun
    local $Cpanel::context = 'ssl';
    local $Cpanel::CPERROR{$Cpanel::context};
    my $ret = Cpanel::AdminBin::run_adminbin_with_status( 'ssl', 'SETPRIMARY', $servername );
    if ( !$ret->{'status'} ) {
        $result->error( 'The system failed to set “[_1]” as the primary SSL host on its IP address because of an error: [_2]', $servername, $ret->{'error'} );
        return;
    }

    return 1;
}

sub _get_sslstorage ($result) {

    # we need the certificate for the subsequent checks
    my $ssl_storage_object = Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();
    if ( !$ssl_storage_object ) {
        $result->error('Unable to open user SSL store.');
        return;
    }

    return $ssl_storage_object;
}

sub _parse_cert_for_install ( $result, $cert ) {
    my ( $status, $parse ) = Cpanel::SSL::Utils::parse_certificate_text($cert);    # PPI NO PARSE - loaded in _init();
    if ( !$status ) {
        $result->error( 'The system could not parse the certificate because of an error: [_1]', $parse );
        return;
    }

    return $parse;
}

sub install_ssl {
    my ( $args, $result ) = @_;
    my ( $domain, $cert, $key, $cabundle ) = $args->get(qw(domain cert key cabundle));

    #Make sure everything is trimmed down.
    for ( $domain, $cert, $key, $cabundle ) {
        _trim( \$_ ) if $_;
    }

    _init();

    if ( !$cert ) {
        $result->error("No 'cert' argument specified.");
        return;
    }

    if ( !$domain ) {
        my ( $status, $ret ) = Cpanel::SSLInfo::getcrtdomain($cert);    # PPI NO PARSE - loaded in _init();
        if ($status) {
            $domain = $ret;
        }
        else {
            $result->raw_error($ret);
            return;
        }
    }

    my $ssl_storage_object = _get_sslstorage($result);
    return if !$ssl_storage_object;

    my $parse = _parse_cert_for_install( $result, $cert );

    my @search_params = _get_key_match_terms($parse);
    my $cert_match    = "@{$parse}{@search_params}";

    my ( $status, $key_id, $key_info_list );

    #Is the given key already saved? If so, use its ID.
    if ($key) {
        ( $status, $key_info_list ) = $ssl_storage_object->find_keys( text => $key );
        if ( !$status ) {
            $result->error( 'The system could not determine if the key is saved to your account because of an error: [_1]', $key_info_list );
            return;
        }
    }

    #If the key isn't already saved, then we check to see
    #if there already is a matching key for the certificate.
    if ( !$key_info_list || !@$key_info_list ) {
        ( $status, $key_info_list ) = $ssl_storage_object->find_keys( %{$parse}{@search_params} );
        if ( !$status ) {
            $result->error( 'An error occurred while searching for matching keys: [_1]', $key_info_list );
            return;
        }
    }

    if ( $key_info_list && @$key_info_list ) {
        $key_id = $key_info_list->[0]->{'id'};
    }

    # If there isn't a key already in the store that matches the certificate, add the one passed in
    if ( !$key_id ) {
        if ( !$key ) {
            $result->error('No key in your account matches the given certificate.');
            return;
        }

        my $key_alg = $parse->key_algorithm();

        ( $status, $parse ) = Cpanel::SSL::Utils::parse_key_text($key);    # PPI NO PARSE - loaded in _init()
        if ( !$status ) {
            $result->error( 'There was an error while parsing the key: [_1]', $parse );
            return;
        }

        my $match_yn = ( $parse->key_algorithm() eq $key_alg );
        $match_yn &&= ( $cert_match eq "@{$parse}{@search_params}" );

        if ( !$match_yn ) {
            $result->error('Certificate and key do not match.');
            return;
        }

        ( $status, my $key_record ) = $ssl_storage_object->add_key( 'text' => $key, 'friendly_name' => $domain );
        if ( !$status ) {
            $result->error( 'There was a problem while saving the key: [_1]', $key_record );
            return;
        }

        $key_id = $key_record->{'id'};
    }

    # Grab the certificates in the store that match the passed in certificate.
    # If there are matching certificates, see if their text is the same as the passed in text
    ( $status, my $certificate_info ) = $ssl_storage_object->find_certificates( 'text' => $cert );
    if ( !$status ) {
        $result->error( 'The system failed to determine whether this certificate is saved in your home directory: [_1]', $certificate_info );
        return;
    }
    my $cert_id;
    if ( $certificate_info && @$certificate_info ) {
        $cert_id = $certificate_info->[0]{'id'};
    }

    # If we didn't find any certificates with text matching the passed in certificate text, add it
    if ( !$cert_id ) {
        my ( $status, $cert_record ) = $ssl_storage_object->add_certificate( 'text' => $cert );
        if ( !$status ) {
            $result->error( 'There was a problem saving the certificate: [_1]', $cert_record );
            return;
        }

        $cert_id = $cert_record->{'id'};
    }

    # Install the certificate
    my $ret = _install( $domain, $cert_id, $key_id, $cabundle, $result );

    # Cache the related data for the caller to use if needed.
    my %data = ( ( ref $ret ? %{$ret} : () ), 'cert_id' => $cert_id, 'key_id' => $key_id );
    $result->data( \%data );

    return ( $ret && ref $ret && $ret->{'status'} ) ? $ret->{'status'} : 0;
}

sub delete_ssl {
    my ( $args, $result ) = @_;
    my ($domain) = $args->get('domain');

    ## note: all known tags do not pass in $domain...
    if ( !$domain ) {
        $domain = $Cpanel::CPDATA{'DNS'};
    }
    if ( !$domain ) {
        Cpanel::Debug::log_warn('domain not provided and Cpanel::CPDATA not initialized');
        $result->error("No domain provided.");
        return;
    }

    ## note: legacy use of CPERROR within &adminrun
    $Cpanel::context = 'ssl';
    my $ret = Cpanel::AdminBin::run_adminbin_with_status( 'ssl', 'DEL', $domain );
    if ( $ret->{'status'} ) {
        $result->message('The SSL host was successfully removed.');
        return 1;
    }
    else {
        $result->error( 'Failed to remove SSL host for “[_1]”: [_2]', $domain, $ret->{'error'} );
        return;
    }
}

sub installed_host {
    my ( $args, $result ) = @_;
    my ($domain) = $args->get('domain');

    if ( !$domain ) {
        $domain = $Cpanel::CPDATA{'DNS'};
    }
    if ( !$domain ) {
        Cpanel::Debug::log_warn('domain not provided and Cpanel::CPDATA not initialized');
        $result->error("No domain provided.");
        return;
    }

    require Cpanel::Config::WebVhosts;
    my $wvh     = Cpanel::Config::WebVhosts->load($Cpanel::user);
    my $vh_name = $wvh->get_vhost_name_for_domain($domain) or do {
        die "No web vhost for domain “$domain”!\n";
    };

    require Cpanel::Apache::TLS;

    # Need to check this first to ensure we don’t slurp up
    # a certificate whose deletion is pending.
    return 1 if !Cpanel::Apache::TLS->has_tls($vh_name);

    my ($path) = Cpanel::Apache::TLS->get_certificates_path($vh_name);

    require Cpanel::SSL::Objects::Certificate::File;
    my $crt_obj = Cpanel::SSL::Objects::Certificate::File->new_if_exists( path => $path );

    if ($crt_obj) {
        require Cpanel::SSL::APIFormat;
        my $crt_hr = Cpanel::SSL::APIFormat::convert_cert_obj_to_api_return($crt_obj);

        my ($verify_cert) = $args->get('verify_certificate');

        my %data = (
            host        => $vh_name,
            certificate => $crt_hr,
        );

        if ($verify_cert) {

            require Cpanel::SSL::Verify;
            my $verify = Cpanel::SSL::Verify->new()->verify(
                $crt_obj->text(),
                $crt_obj->get_extra_certificates(),
            );

            $data{'verify_error'} = $verify->get_error_string();

        }

        require Cpanel::DomainLookup;
        my %MULTIPARKED = Cpanel::DomainLookup::getmultiparked();
        if ( exists $MULTIPARKED{$vh_name} ) {
            $data{'aliases'} = [ sort keys %{ $MULTIPARKED{$vh_name} } ];
        }
        $result->data( \%data );
    }

    return 1;
}

sub installed_hosts {
    my ( $args, $result ) = @_;

    if ( !$INSTALLED_HOSTS_SSL_DB_FILE ) {
        require Cpanel::Apache::TLS;
        $INSTALLED_HOSTS_SSL_DB_FILE = Cpanel::Apache::TLS->get_mtime_path();
    }
    my $ret = Cpanel::AdminBin::fetch_adminbin_with_status( 'ssl', $INSTALLED_HOSTS_SSL_DB_FILE, 'FETCHINSTALLEDHOSTS', 'storable' );
    if ( !$ret->{'status'} ) {
        $result->error( "Unable to retrieve the installed hosts: [_1]", $ret->{'error'} );
        return;
    }
    my $result_hr = $ret->{'data'};
    my $host_objs = $result_hr->{'hosts'};

    require Cpanel::WebVhosts;
    my %fqdn_vhost;
    for my $vh ( Cpanel::WebVhosts::list_vhosts($Cpanel::user) ) {
        next if !$vh->{'vhost_is_ssl'};
        @fqdn_vhost{ @{ $vh->{'domains'} } } = ($vh) x @{ $vh->{'domains'} };
    }

    if ( ref $host_objs eq 'ARRAY' ) {
        require Cpanel::DomainLookup;
        my %MULTIPARKED = Cpanel::DomainLookup::getmultiparked();

        require Cpanel::DomainLookup::DocRoot;
        my $docroots_ref = Cpanel::DomainLookup::DocRoot::getdocroots();

        my @sslcerts;
        foreach my $host_obj (@$host_objs) {
            if ( exists( $host_obj->{'ip'} ) ) {
                $host_obj->{'ip'} = Cpanel::NAT::get_public_ip( $host_obj->{'ip'} );
            }
            my $servername = $host_obj->{'servername'};

            #Shouldn’t happen in production but came up while
            #developing Apache TLS.
            my $vh = $fqdn_vhost{$servername} or do {
                Cpanel::Debug::log_warn("$servername from admin not in list_vhosts: userdata corruption?");
                next;
            };

            my %data = (
                %$host_obj,
                docroot => $docroots_ref->{$servername},
                domains => [
                    sort( $servername,
                        ( $MULTIPARKED{$servername} ? keys %{ $MULTIPARKED{$servername} } : () ),
                    )
                ],
                fqdns => [
                    sort( @{ $vh->{'domains'} },
                        @{ $vh->{'proxy_subdomains'} },
                    ),
                ],
                mail_sni_status => 1,
            );

            push @sslcerts, \%data;
        }
        $result->data( \@sslcerts );
    }

    return 1;
}

sub is_sni_supported {
    my ( $args, $result ) = @_;

    $result->data(1);
    $result->message('cPanel & WHM always supports SNI from now on.');

    return 1;
}

sub is_mail_sni_supported {
    my ( $args, $result ) = @_;

    $result->data(1);
    $result->message('cPanel & WHM always supports mail SNI from now on.');

    return 1;
}

#
#  get_cn_name
#
#  $domain can be a DOMAIN, USER, or EMAIL ADDRESS
#  this eventually gets passed to Cpanel::SSL::Domain::get_best_ssldomain_for_object
#  which knows about this legacy quirk and can handle it
#
#  We have to support them all for legacy reasons as this argument gets fed from getcnname
#  Example Legacy Usage:
#  <li><cptext 'SSL Incoming Mail Server'>: <strong><cpanel SSL="getcnname($RAW_FORM{'acct'},'imap')"></strong></li>
#
sub get_cn_name {
    my ( $args, $result ) = @_;
    my ( $domain, $service, $add_mail_subdomain ) = $args->get( 'domain', 'service', 'add_mail_subdomain' );
    $add_mail_subdomain = $add_mail_subdomain ? 1 : 0;

    if ( !$service ) {
        Cpanel::Debug::log_warn('Failed to provide service argument');
        return;
    }

    if ( $service eq 'imap' || $service eq 'pop3' ) {
        $service = sprintf( "%s_%s", 'dovecot', $service );
    }

    _init();

    my $ssl_service_group = Cpanel::SSL::ServiceMap::lookup_service_group($service);    # PPI NO PARSE - loaded in _init()
    return if ( !$ssl_service_group );

    my ( $ok, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $domain, { 'service' => $ssl_service_group, 'add_mail_subdomain' => $add_mail_subdomain } );    # PPI NO PARSE - loaded in _init()

    if ($ok) {
        foreach my $key ( keys %{$ssl_domain_info} ) {
            $Cpanel::CPVAR{$key} = $ssl_domain_info->{$key};
        }
        $result->data($ssl_domain_info);
    }
    else {
        $result->raw_error($ssl_domain_info);
    }
    return 1;
}

=back

=head2 get_autossl_excluded_domains

The UAPI function to get the AutoSSL excluded domains for the user.

=head3 Input

=over 3

=item C<NONE> None

    None

=back

=head3 Output

=over 3

=item C<ARRAYREF> of C<HASHREF>s

    An arrayref of the form:
    [
      { 'domain' => 'domain.tld' },
      { 'domain' => 'domain2.tld' },
      ...
    ]

=back

=head3 Exceptions

=over 3

=item Anything Cpanel::SSL::Auto::Exclude::Get::get_user_excluded_domains can throw

=back

=cut

sub get_autossl_excluded_domains {
    my ( $args, $result ) = @_;

    require Cpanel::SSL::Auto::Exclude::Get;

    my @domains = Cpanel::SSL::Auto::Exclude::Get::get_user_excluded_domains($Cpanel::user);

    $result->data( [ map { { 'excluded_domain' => $_ } } @domains ] );
    return 1;
}

=head2 set_autossl_excluded_domains

The UAPI function to set the AutoSSL excluded domains for the user.

=head3 Input

=over 3

=item C<SCALAR> domains

    Domains is scalar of domain names separated by a comma character ',' representing an array. Please note that this is a SET command
    therefore the data passed in will replace whatever data is stored in the excludes file already.

=back

=head3 Output

=over 3

=item C<NONE> None

    None.

=back

=head3 Exceptions

=over 3

=item Anything The AdminBin ssl_call function SET_AUTOSSL_EXCLUDED_DOMAINS can throw

=back

=cut

sub set_autossl_excluded_domains {
    my ($args) = @_;

    my ($domains_str) = $args->get('domains');
    my @domains = defined $domains_str ? split( m/,/, $domains_str ) : ();

    Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'SET_AUTOSSL_EXCLUDED_DOMAINS', \@domains );

    return 1;
}

sub _get_required_domains_arg_or_die {
    my ($args) = @_;

    return split( m/,/, $args->get_length_required('domains') );
}

=head2 add_autossl_excluded_domains

The UAPI function to add to the AutoSSL excluded domains for the user.

=head3 Input

=over 3

=item C<SCALAR> domains

    Domains is scalar of domain names separated by a comma character ',' representing an array.

=back

=head3 Output

=over 3

=item C<NONE> None

    None.

=back

=head3 Exceptions

=over 3

=item Anything The AdminBin ssl_call function ADD_AUTOSSL_EXCLUDED_DOMAINS can throw

=back

=cut

sub add_autossl_excluded_domains {
    my ($args) = @_;

    my @domains = _get_required_domains_arg_or_die($args);

    # Domain string length cannot exceed 255, plus 1 for the comma delimiter == 2^8. Further divide the value in half as a safety margin.
    my $BATCH_SIZE = $Cpanel::AdminBin::Serializer::MAX_LOAD_LENGTH >> 9;
    for ( my $start_index = 0; $start_index < scalar(@domains); $start_index += $BATCH_SIZE ) {
        my $end_index = Cpanel::ArrayFunc::min( $start_index + $BATCH_SIZE, scalar(@domains) ) - 1;
        Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'ADD_AUTOSSL_EXCLUDED_DOMAINS', [ @domains[ $start_index .. $end_index ] ] );
    }

    return 1;
}

=head2 remove_autossl_excluded_domains

The UAPI function to remove from the AutoSSL excluded domains for the user.

=head3 Input

=over 3

=item C<SCALAR> domains

    Domains is scalar of domain names separated by a comma character ',' representing an array.

=back

=head3 Output

=over 3

=item C<NONE> None

    None.

=back

=head3 Exceptions

=over 3

=item Anything The AdminBin ssl_call function REMOVE_AUTOSSL_EXCLUDED_DOMAINS can throw

=back

=cut

sub remove_autossl_excluded_domains {
    my ($args) = @_;

    my @domains = _get_required_domains_arg_or_die($args);

    # Domain string length cannot exceed 255, plus 1 for the comma delimiter == 2^8. Further divide the value in half as a safety margin.
    my $BATCH_SIZE = $Cpanel::AdminBin::Serializer::MAX_LOAD_LENGTH >> 9;
    for ( my $start_index = 0; $start_index < scalar(@domains); $start_index += $BATCH_SIZE ) {
        my $end_index = Cpanel::ArrayFunc::min( $start_index + $BATCH_SIZE, scalar(@domains) ) - 1;
        Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'REMOVE_AUTOSSL_EXCLUDED_DOMAINS', [ @domains[ $start_index .. $end_index ] ] );
    }

    return 1;
}

=head2 start_autossl_check

No inputs; just wraps ssl_call/START_AUTOSSL_CHECK admin call.

=cut

sub start_autossl_check {

    Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'START_AUTOSSL_CHECK' );

    return 1;
}

=head2 is_autossl_check_in_progress

No inputs; just wraps ssl_call/IS_AUTOSSL_CHECK_IN_PROGRESS admin call.

=cut

sub is_autossl_check_in_progress {
    my ( $args, $result ) = @_;

    my $ret = Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'IS_AUTOSSL_CHECK_IN_PROGRESS' );

    $result->data($ret);

    return 1;
}

=head2 get_autossl_problems

No inputs; just wraps ssl_call/GET_AUTOSSL_PROBLEMS admin call.

=cut

sub get_autossl_problems {
    my ( $args, $result ) = @_;

    my $problems_ar = Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'GET_AUTOSSL_PROBLEMS' );

    $result->data($problems_ar);

    return 1;
}

##################################################
## UTILITY FUNCTIONS (NON-API FUNCTIONS)
## functions moved from Cpanel::SSL in order to reduce the binary size of uapi.pl

sub _save_key {
    my ( $result, $key, $opts ) = @_;

    _init();

    #$sslstorage ||= Cpanel::SSLStorage::User->new();
    my ( $ok, $sslstorage ) = Cpanel::SSLStorage::User->new( 'rename_old_friendly_name' => $opts->{'rename_old_fn'} );    # PPI NO PARSE - loaded in _init();
    if ( !$ok ) {
        $result->raw_error($sslstorage);
        return undef;
    }

    my $record;
    ( $ok, $record ) = $sslstorage->add_key( text => $key, friendly_name => $opts->{'friendly_name'} );

    if ( !$ok ) {
        $result->raw_error($record);
        return undef;
    }

    return $record;
}

my %_countries_lookup;

sub _check_country {
    my ($item) = @_;

    if ( !%_countries_lookup ) {
        require Cpanel::CountryCodes;
        %_countries_lookup = map { $_ => undef } @{ Cpanel::CountryCodes::COUNTRY_CODES() };
    }

    return $item && exists $_countries_lookup{$item} ? 1 : 0;
}

sub _check_organization {
    my ($item) = @_;

    return length($item) && _max_64_bytes($item);    # ub-organization-name = 64
}

sub _check_organizationalUnit {
    my ($item) = @_;

    return !$item || _max_64_bytes($item);           # ub-organizational-unit-name = 64
}

sub _max_64_bytes {
    return ( length(shift) <= 64 ) ? 1 : 0;
}

sub _has_length {
    return length(shift) ? 1 : 0;
}

sub _checkssldata {
    my %OPTS = @_;

    require Cpanel::CheckData;
    my %check_routines = (
        countryName            => \&_check_country,
        stateOrProvinceName    => \&_has_length,
        localityName           => \&_has_length,
        organizationName       => \&_check_organization,
        organizationalUnitName => \&_check_organizationalUnit,
        emailAddress           => \&Cpanel::CheckData::is_empty_or_valid_email,
        pass                   => \&_validsslpass
    );

    if ( $OPTS{'type'} eq 'crt' ) { delete $OPTS{'pass'}; }

    delete $OPTS{'type'};

    foreach my $opt ( keys %OPTS ) {
        my $ok;
        eval { $ok = $check_routines{$opt}->( $OPTS{$opt} ) if exists $check_routines{$opt}; };
        if ( !$ok ) { return ( 0, $opt ); }
    }
    return 1;
}

sub _validsslpass {
    my ($pass) = @_;
    return 1 if !$pass || $pass eq '';
    return   if $pass =~ tr{\r\n}{};
    return   if ( length($pass) < 4 );
    return 1;
}

sub _install {
    my ( $domain, $crt_id, $key_id, $cab_data, $result ) = @_;

    my $certificate_domain = $domain;
    $domain =~ s/^www\.//i;

    $Cpanel::context = 'ssl';

    require Cpanel::Validate::Domain;
    if ( !$domain || !Cpanel::Validate::Domain::valid_wild_domainname($domain) ) {
        $result->error('Invalid host specified. Unable to continue.');
        return;
    }

    _init();

    # Install the certificate
    my %opts = (
        'domain'         => $domain,
        'certificate_id' => $crt_id,
        'key_id'         => $key_id,
        ($cab_data) ? ( 'cabundle_text' => $cab_data ) : (),
    );

    my $ret = Cpanel::AdminBin::fetch_adminbin_nocache_with_status( 'ssl', undef, 'ADD', 'storable', \%opts );
    if ( !$ret->{'status'} ) {
        $result->error( 'The certificate could not be installed on the domain “[_1]”.', $domain );
        $result->raw_error( _extract_error($ret) );
        return;
    }
    my $output = $ret->{'data'};

    if ( $output && $output->{'aliases'} && ref $output->{'aliases'} ne 'ARRAY' ) {
        $output->{'aliases'} = [ split m{\s+}, $output->{'aliases'} ];
    }

    $result->data($output);

    if ( !$output->{'status'} ) {
        $result->error( 'The certificate could not be installed on the domain “[_1]”.', $domain );
        $result->raw_error( _extract_error($ret) );
        return;
    }
    $result->message( 'The certificate was successfully installed on the domain “[_1]”.', $domain );
    return $output;
}

sub _extract_error {
    my $result = shift;
    if ( ref $result->{'error'} eq 'HASH' ) {
        if ( $result->{'error'}{'statusmsg'} eq $result->{'error'}{'message'} ) {
            return $result->{'error'}{'message'};
        }
        return $result->{'error'}{'statusmsg'} . ': ' . $result->{'error'}{'message'};
    }
    if ( $result->{'error'} && !ref $result->{'error'} ) {
        return $result->{'error'};
    }

    # last resort: anything that might be meaningful
    return $result->{'message'} || $result->{'data'} || 'unknown error';
}

sub _get_openssl {
    my ($result) = @_;

    _init();
    my $openssl = Cpanel::OpenSSL->new();    # PPI NO PARSE - loaded in _init()
    if ( !$openssl ) {
        $result->error( 'The “[_1]” binary could not be located.', 'openssl' );
        return;
    }

    return $openssl;
}

sub _is_safe_path {
    return $_[0] !~ tr{|/}{} && $_[0] !~ m{\A\.};
}

sub _get_search_args {
    my ( $args, $result ) = @_;

    my ( $id, $friendly_name ) = $args->get( 'id', 'friendly_name' );
    if ( length $id ) {
        if ( !_is_safe_path($id) ) {
            if ($result) {
                $result->error( 'The “[_1]” parameter is invalid.', 'id' );
            }
            return;
        }

        return ( 'id' => $id );
    }

    if ( length $friendly_name ) {
        return ( 'friendly_name' => $friendly_name );
    }

    if ($result) {
        $result->error( 'You must specify either the “[_1]” or “[_2]”.', 'id', 'friendly_name' );
    }
    return;
}

my %_friendly_name_setter = (
    key         => 'set_key_friendly_name',
    certificate => 'set_certificate_friendly_name',
    csr         => 'set_csr_friendly_name',
);

my %_deleter = (
    key         => 'remove_key',
    certificate => 'remove_certificate',
    csr         => 'remove_csr',
);

my %_finder = (
    key         => 'find_keys',
    certificate => 'find_certificates',
    csr         => 'find_csrs',
);

sub _set_friendly_name {
    my ( $args, $result, $type ) = @_;

    my $new_name = $args->get('new_friendly_name');
    if ( !length $new_name ) {
        $result->error( 'You must specify the “[_1]”.', 'new_friendly_name' );
        return;
    }
    _init();
    $sslstorage ||= eval { Cpanel::SSLStorage::User->new() };    # PPI NO PARSE - loaded in _init();
    if ( !$sslstorage ) {                                        # PPI NO PARSE - loaded in _init();
        $result->raw_error($@);
        return;
    }

    my %search_args = _get_search_args( $args, $result ) or return;
    my $id          = $search_args{'id'};
    if ( !$id ) {
        my $find_func = $_finder{$type};
        my $code      = $sslstorage->can($find_func);
        die ref($sslstorage) . " cannot '$find_func'!\n" if !$code;

        my ( $ok, $found ) = $code->( $sslstorage, %search_args );
        if ( !$ok ) {
            $result->raw_error($found);
            return;
        }
        elsif ( !$found || !@$found ) {
            $result->raw_error('No record matches the search term.');
            return;
        }

        $id = $found->[0]{'id'};
    }

    my $setter_func = $_friendly_name_setter{$type};
    my ( $ok, $msg ) = $sslstorage->$setter_func( $id, $new_name );
    if ( !$ok ) {
        $result->raw_error($msg);
        return;
    }

    return 1;
}

sub _delete {
    my ( $args, $result, $type ) = @_;

    my %search_args = _get_search_args( $args, $result ) or return;

    _init();
    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init();

    my $find_func = $_finder{$type};
    my $coderef   = $sslstorage->can($find_func);
    die ref($sslstorage) . " cannot '$find_func'!\n" if !$coderef;
    my ( $ok, $items_ar ) = $coderef->( $sslstorage, %search_args );
    if ( !$ok ) {
        $result->error( 'The system failed to find matching records because of an error: [_1]', $items_ar );
        return;
    }

    #Nothing to delete!
    return 1 if !@$items_ar;

    my $id = $items_ar->[0]{'id'};

    my $delete_func = $_deleter{$type};
    my $error;
    ( $ok, $error ) = $sslstorage->$delete_func( 'id' => $id );

    if ( !$ok ) {
        $result->raw_error($error);
        return;
    }

    $result->data($items_ar);

    return 1;
}

sub _get_key_match_terms ($sslstorage_obj_hr) {
    return Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $sslstorage_obj_hr,
        rsa   => sub { 'modulus' },
        ecdsa => sub { ( 'ecdsa_curve_name', 'ecdsa_public' ) },
    );
}

sub _find_matching_key_search_terms {
    my ( $args, $result ) = @_;

    my @search_args = _get_search_args( $args, $result ) or return;

    _init();
    $sslstorage ||= Cpanel::SSLStorage::User->new();    # PPI NO PARSE - loaded in _init()

    #Find the key's search terms.
    my ( $ok, $key_data ) = $sslstorage->find_keys(@search_args);
    if ( !$ok ) {
        $result->error( 'An error occurred while looking for the key: [_1]', $key_data );
        return;
    }
    if ( !$key_data || !@$key_data ) {
        $result->error('No key matches that search term.');
        return;
    }

    my @names = _get_key_match_terms( $key_data->[0] );

    return map { $_ => $key_data->[0]{$_} } @names;
}

sub _trim {
    my $str_r = shift;
    $$str_r =~ s{\A\s+|\s+\z}{}g;
    $$str_r =~ s/\s*\n\s*/\n/g;
    return;
}

#for testing
sub _reset_sslstorage {
    $sslstorage = undef;
    return;
}

=head1 SSL REDIRECTS

=head2 can_ssl_redirect()

Determines if the server can automatically redirect to SSL for vhosts.

=head3 Parameters:

None.

=head3 Return Value:

=over 4

=item Boolean - True if the server can auto redirect user vhosts to SSL, false otherwise.

=back

=cut

sub can_ssl_redirect {
    my ( $args, $result ) = @_;

    #Can't very well redirect if admins have disabled SSL AND have no autossl providers
    require Cpanel::Config::LoadCpConf;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf();
    if ( defined $cpconf->{'allowcpsslinstall'} && !$cpconf->{'allowcpsslinstall'} ) {

        #Adminbins are slower than cpconf load
        require Cpanel::AdminBin::Call;
        my $provider = Cpanel::AdminBin::Call::call( 'Cpanel', 'ssl_call', 'GET_AUTOSSL_PROVIDER' );

        $result->error('The administrator has disabled the “allowcpsslinstall” feature on this server, and autossl is disabled.') unless $provider;
    }

    require Cpanel::ConfigFiles::Apache::modules;
    if ( !Cpanel::ConfigFiles::Apache::modules::is_supported('mod_rewrite') ) {
        $result->error("Apache mod_rewrite is not installed.");
    }

    require Cpanel::Pkgr;

    my $vhost = Cpanel::Pkgr::get_package_version("ea-apache24-config-runtime");
    $result->error("EA4 configuration not installed!") unless defined $vhost;

    if ( defined $vhost ) {
        my ( $major, $minor ) = ( 0, 0 );
        ( $major, $minor ) = $vhost =~ m/(\d+\.\d+)-(\d+)/a;
        $result->error("Please update the ea-apache24-config-runtime to version 1.0-140 or better") unless $major >= 1.0 && $minor >= 140;

        require Cpanel::ConfigFiles::Apache::local;
        my @vhost_templates = grep { /vhost/ } Cpanel::ConfigFiles::Apache::local::get_installed_local_apache_template_paths();

        if (@vhost_templates) {
            $result->error("Custom Apache vhost templates are in use.");
        }
    }

    if ( $result->errors() ) {
        return $result->data(0);
    }

    $result->message("Server can redirect to ssl for user domains.");
    return $result->data(1);
}

=head2 toggle_https_redirect_for_domains(HASHREF parameters)

Turn on or off HTTPS redirects for the vhosts listening on the provided domains.
Requires that the host satisfy the following conditions when enabling HTTPS:

    * Has a currently valid SSL certificate configured for each passed domain.
    * Has AutoSSL enabled for their owning user.

Furthermore, the calling user must own the domains provided; any not owned by them will be skipped and a warning emitted to the log.

=head3 Parameters:

=over 4

=item B<domains> - array - The domains for which you wish to enable/disable HTTPS redirects for their vhosts.  Also acceptable as a CSV string.

=item B<state> - boolean - false will disable redirects, while true will enable redirects.

=back

=head3 Return Value:

=over 4

=item arrayref - the list of domains for which action was actually taken.

=back

=head3 Termination Conditions:

If any of the host requirements mentioned above fail, this will emit an error rather than continuing.

=head3 Side-Effects

This will queue a rebuild of the apache configuration and a graceful restart of the apache server.

=head3 Notes

It is the caller's responsibility to call can_ssl_redirect() before this function.
Doing so when you can't redirect shouldn't be harmful, but it won't have any practical effect other than queueing an apache restart.

=cut

sub toggle_ssl_redirect_for_domains {
    my ( $args, $result ) = @_;

    #strip useless structure
    $args = $args->{_args};
    $args->{domains} = [ split( /,/, $args->{domains} ) ] if ref $args->{domains} ne "ARRAY";

    #Nothing to do
    return unless ( scalar( @{ $args->{domains} } ) );

    my @args = map {
        {
            ssl_redirect    => $_,
            no_cache_update => 1,
        }
    } @{ $args->{domains} };
    $args[-1]{no_cache_update} = 0;

    local $@;
    my @domains_acted_upon;
    @domains_acted_upon = eval { Cpanel::AdminBin::Call::call( "Cpanel", "https_redirects", "ADD_REDIRECTS_FOR_DOMAINS",    \@args ) if int( $args->{state} ) };
    @domains_acted_upon = eval { Cpanel::AdminBin::Call::call( "Cpanel", "https_redirects", "REMOVE_REDIRECTS_FOR_DOMAINS", \@args ) unless int( $args->{state} ) };

    $result->error("One or more domains passed failed to validate.") if $@;

    $result->data( \@domains_acted_upon );
    return 1;
}

1;
