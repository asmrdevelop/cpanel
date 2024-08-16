package Cpanel::SSL;

# cpanel - Cpanel/SSL.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel             ();
use Cpanel::Debug      ();
use Cpanel::InMemoryFH ();
use Cpanel::API        ();
use Cpanel::API::SSL   ();

*_validsslpass = *Cpanel::API::SSL::_validsslpass;

my @api1_subject_order = qw(
  domains
  countryName
  stateOrProvinceName
  localityName
  organizationName
  organizationalUnitName
  emailAddress
);

my %api2_to_uapi_subject = (
    'city'            => 'localityName',
    'company'         => 'organizationName',
    'companydivision' => 'organizationalUnitName',
    'country'         => 'countryName',
    'email'           => 'emailAddress',
    'host'            => 'domains',                  #not really in the "subject", but hey
    'state'           => 'stateOrProvinceName',
);

## note: _genkey, _gencsr, and _gencrt have been inlined in ::API::SSL

our $VERSION = '1.2';

{
    my $init;

    sub _init {
        return if $init;

        # avoid to compile in shipped Cpanel::SSL* modules in cpanel.pl
        #   lazy load the modules at run time

        # use multiple lines for PPI parsing purpose
        require Cpanel::SSLStorage::User;
        require Cpanel::SSLInfo;
        require Cpanel::SSLStorage::Utils;

        return 1;
    }
}

sub SSL_init { }

##################################################
## cpdev: KEYS

## DEPRECATED!
sub api2_listkeys {
    my $items = _lister('key');
    return [ map { { host => $_ } } @$items ];
}

## DEPRECATED!
sub SSL_listkeys {
    my $data_ref = _lister('key');
    if ( scalar @$data_ref ) {
        eval 'require Cpanel::Encoder::Tiny' if !$INC{'Cpanel/Encoder/Tiny.pm'};
        for my $hr_host (@$data_ref) {
            print Cpanel::Encoder::Tiny::safe_html_encode_str("$hr_host\n");
        }
    }
    else {
        print "No SSL KEYs Found";
    }
    return;
}

## DEPRECATED!
sub SSL_listkeysopt {
    my $data_ref = _lister('key');
    if ( scalar @$data_ref ) {
        eval 'require Cpanel::Encoder::Tiny' if !$INC{'Cpanel/Encoder/Tiny.pm'};
        foreach my $hr_host (@$data_ref) {
            my $html_fn = Cpanel::Encoder::Tiny::safe_html_encode_str($hr_host);
            print qq{<option value="$html_fn">$html_fn</option>\n};
        }
    }
    else {
        print qq{<option value="">No Keys Exist</option>\n};
    }
    return;
}

## DEPRECATED!
sub SSL_showkey {
    my ( $host, $textmode ) = @_;
    my $id       = _find_key_id_for_domain($host) or return;
    my $result   = Cpanel::API::wrap_deprecated( "SSL", "show_key", { id => $id } );
    my $data_ref = $result->data() || {};
    if ($textmode) {
        print $data_ref->{'text'};
    }
    else {
        print $data_ref->{'key'};
    }
    return;
}

## DEPRECATED!
sub api2_genkey {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my %CFG = ( @_, 'api.quiet' => 1, '_api2_legacy_rename_old_friendly_name_never_use_this' => 1 );

    require Cpanel::Validate::Domain;
    if ( !Cpanel::Validate::Domain::valid_wild_domainname( $CFG{'host'} ) ) {
        return {
            result => 0,
            output => q{},
            key    => undef,
        };
    }

    #NOTE: As of early 2013, this CHANGED from a default of 1024.
    if ( !$CFG{'keysize'} || $CFG{'keysize'} !~ m{\A\d+\z} ) {
        require Cpanel::OpenSSL;
        $CFG{'keysize'} = $Cpanel::OpenSSL::DEFAULT_KEY_SIZE;
    }
    elsif ( $CFG{'keysize'} > 4096 ) {
        $CFG{'keysize'} = 4096;
    }

    $CFG{'friendly_name'} = delete $CFG{'host'};
    my $result   = Cpanel::API::wrap_deprecated( "SSL", "generate_key", \%CFG );
    my $data_ref = $result->data() || {};

    return {
        result => $result->status(),
        output => $result->status() && 'Private key generated!' || $result->errors_as_string() || q{},
        key    => $data_ref->{'text'},
    };
}

## DEPRECATED!
sub SSL_genkey {
    my ( $host, $keysize ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "SSL", "generate_key", { friendly_name => $host, keysize => $keysize, '_api2_legacy_rename_old_friendly_name_never_use_this' => 1 } );
    return $result->status();
}

## DEPRECATED!
sub api2_uploadkey {
    my %CFG  = @_;
    my $args = { 'api.quiet' => 1, '_api2_legacy_rename_old_friendly_name_never_use_this' => 1 };

    if ( exists $CFG{'host'} ) {
        $args->{'friendly_name'} = $CFG{'host'};
    }
    if ( exists $CFG{'key'} ) {
        $args->{'key'} = $CFG{'key'};
    }

    my $result = Cpanel::API::wrap_deprecated( "SSL", "upload_key", $args );
    return { result => $result->status(), output => $result->messages_as_string() };
}

## DEPRECATED!
sub SSL_uploadkey {
    ## arguments come in as a hash-ref
    my ($args) = @_;
    $args->{'friendly_name'} = delete $args->{'domain'};
    my $result = Cpanel::API::wrap_deprecated( "SSL", "upload_key", { %$args, '_api2_legacy_rename_old_friendly_name_never_use_this' => 1 } );
    return $result->status();
}

## DEPRECATED!
sub SSL_deletekey {
    my ($host) = @_;
    my $id     = _find_key_id_for_domain($host) or return;
    my $result = Cpanel::API::wrap_deprecated( "SSL", "delete_key", { 'id' => $id } );
    return $result->status();
}

##################################################
## cpdev: CSRS

## DEPRECATED!
sub api2_listcsrs {
    my $items = _lister('csr');
    return [ map { { host => $_ } } @$items ];
}

## DEPRECATED!
sub SSL_listcsrs {
    my $data_ref = _lister('csr');

    if ( scalar @$data_ref ) {
        eval 'require Cpanel::Encoder::Tiny' if !$INC{'Cpanel/Encoder/Tiny.pm'};
        for my $hr_host (@$data_ref) {
            print Cpanel::Encoder::Tiny::safe_html_encode_str($hr_host) . "\n";
        }
    }
    else {
        print "No SSL CSRs Found";
    }
    return;
}

## DEPRECATED!
sub SSL_listcsrsopt {
    my $data_ref = _lister('csr');
    if ( scalar @$data_ref ) {
        eval 'require Cpanel::Encoder::Tiny' if !$INC{'Cpanel/Encoder/Tiny.pm'};
        foreach my $hr_host (@$data_ref) {
            my $html_fn = Cpanel::Encoder::Tiny::safe_html_encode_str($hr_host);
            print qq{<option value="$html_fn">$html_fn</option>\n};
        }
    }
    return;
}

## DEPRECATED!
sub SSL_showcsr {
    my ( $host, $textmode ) = @_;

    _init();

    my $sslstorage = Cpanel::SSLStorage::User->new();
    my ( $ok, $csrs ) = $sslstorage->find_csrs( 'friendly_name' => $host );
    return if !$ok || !@$csrs;

    my $result   = Cpanel::API::wrap_deprecated( "SSL", "show_csr", { id => $csrs->[0]{'id'} } );
    my $data_ref = $result->data() || {};
    if ($textmode) {
        print $data_ref->{'text'};
    }
    else {
        print $data_ref->{'csr'};
    }
    return;
}

## DEPRECATED!
sub api2_gencsr {
    my %CFG  = @_;
    my $pass = delete $CFG{'pass'};
    %CFG = (
        ( map { $api2_to_uapi_subject{$_} => $CFG{$_} } keys %CFG ),
        'pass'                                                 => ( $pass || '' ),
        'api.quiet'                                            => 1,
        '_api2_legacy_rename_old_friendly_name_never_use_this' => 1,
    );
    $CFG{'key_id'} = _find_key_id_for_domain( $CFG{'domains'} ) or do {
        return { output => q{}, result => 0 };
    };

    my $result = Cpanel::API::wrap_deprecated( "SSL", "generate_csr", \%CFG );
    return { result => $result->status(), output => $result->messages_as_string() };
}

## DEPRECATED!
## note: this is an unfortunate method that looses brevity with a named parameter requirement
## x3: <cpanel SSL="gencsr($FORM{'host'},$FORM{'country'},$FORM{'state'},$FORM{'city'},
##   $FORM{'company'},$FORM{'companydivision'},$FORM{'email'},$FORM{'pass'})">
sub SSL_gencsr {
    my %args = ( '_api2_legacy_rename_old_friendly_name_never_use_this' => 1 );
    @args{ @api1_subject_order, 'pass' } = @_;
    $args{'key_id'} = _find_key_id_for_domain( $args{'domains'} ) or return;
    my $result = Cpanel::API::wrap_deprecated( "SSL", "generate_csr", \%args );
    return $result->status();
}

## DEPRECATED!
sub SSL_deletecsr {
    my ($host) = @_;

    _init();

    my $sslstorage = Cpanel::SSLStorage::User->new();
    my ( $ok, $csrs ) = $sslstorage->find_csrs( 'friendly_name' => $host );
    return if !$ok || !@$csrs;

    my $result = Cpanel::API::wrap_deprecated( "SSL", "delete_csr", { id => $csrs->[0]{'id'} } );
    return $result->status();
}

##################################################
## cpdev: CERTS

## DEPRECATED!
sub api2_listcrts {
    my $items = _lister('certificate');

    my @results;
    for my $item (@$items) {

        tie *MEMORY_FH, 'Cpanel::InMemoryFH';
        select MEMORY_FH;
        SSL_showcrt( $item, 1 );
        select STDOUT;

        my $parsed;
        read( MEMORY_FH, $parsed, 999999 );

        $parsed =~ /\s+CN\s*=\s*([^\s,]+)/m;
        my $issuer = $1;
        $issuer =~ s/\/.*$//g;

        $parsed =~ /Not\s+After\s*:\s*([^\n]*)/m;
        my $expire = $1;

        my $new_item = {
            host       => $item,
            issuer     => $issuer,
            ssltxt     => $parsed,
            expiredate => $expire,
        };
        push @results, $new_item;
    }

    return \@results;
}

## DEPRECATED!
sub SSL_listcrts {
    my $data_ref = _lister('certificate');
    if ( scalar @$data_ref ) {
        eval 'require Cpanel::Encoder::Tiny' if !$INC{'Cpanel/Encoder/Tiny.pm'};
        for my $hr_host (@$data_ref) {
            print Cpanel::Encoder::Tiny::safe_html_encode_str($hr_host) . "\n";
        }
    }
    else {
        print "No SSL CRTs Found";
    }
    return;
}

## DEPRECATED!
sub SSL_listcrtsopt {
    my $data_ref = _lister('certificate');

    if ( scalar @$data_ref ) {
        eval 'require Cpanel::Encoder::Tiny' if !$INC{'Cpanel/Encoder/Tiny.pm'};
        foreach my $hr_host (@$data_ref) {
            my $html_fn = Cpanel::Encoder::Tiny::safe_html_encode_str($hr_host);
            print qq{<option value="$html_fn">$html_fn</option>\n};
        }
    }
    return;
}

## DEPRECATED!
sub SSL_showcrt {
    my ( $host, $textmode ) = @_;

    _init();

    my $sslstorage = Cpanel::SSLStorage::User->new();
    my ( $ok, $certs ) = $sslstorage->find_certificates( 'friendly_name' => $host );
    return if !$ok || !@$certs;

    my $result   = Cpanel::API::wrap_deprecated( "SSL", "show_cert", { id => $certs->[0]{'id'} } );
    my $data_ref = $result->data() || {};
    if ($textmode) {
        print $data_ref->{'text'};
    }
    else {
        print $data_ref->{'cert'};
    }
    return;
}

## DEPRECATED!
sub api2_gencrt {
    my %CFG  = @_;
    my $pass = delete $CFG{'pass'};
    %CFG = (
        ( map { $api2_to_uapi_subject{$_} => $CFG{$_} } keys %CFG ),
        'api.quiet'                                            => 1,
        '_api2_legacy_rename_old_friendly_name_never_use_this' => 1,
    );
    $CFG{'key_id'} = _find_key_id_for_domain( $CFG{'domains'} ) or do {
        return { result => 0, output => q{} };
    };

    my $result = Cpanel::API::wrap_deprecated( "SSL", "generate_cert", \%CFG );

    return { result => $result->status(), output => $result->messages_as_string() };
}

## DEPRECATED!
sub SSL_gencrt {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my %args = ( '_api2_legacy_rename_old_friendly_name_never_use_this' => 1 );
    @args{@api1_subject_order} = @_;
    $args{'key_id'} = _find_key_id_for_domain( $args{'domains'} ) or return;
    my $result = Cpanel::API::wrap_deprecated( "SSL", "generate_cert", \%args );
    return $result->status();
}

## DEPRECATED!
sub api2_uploadcrt {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my %CFG = ( @_, 'api.quiet' => 1, '_api2_legacy_rename_old_friendly_name_never_use_this' => 1 );

    if ( length $CFG{'host'} ) {
        require Cpanel::Validate::Domain;
        return { result => 0, output => q{} } if !Cpanel::Validate::Domain::valid_wild_domainname( $CFG{'host'} );
    }

    $CFG{'friendly_name'} = delete $CFG{'host'};
    my $result = Cpanel::API::wrap_deprecated( "SSL", "upload_cert", \%CFG );

    return { result => 0, output => q{} } if !$result->status();

    my $data = $result->data();

    return {
        result => $result->status,
        output => "$data->[0]{'subject.commonName'} (auto-detected)",
    };
}

## DEPRECATED!
sub SSL_uploadcrt {
    ## arguments come in as a hash-ref
    my ($args) = @_;
    $args->{'_api2_legacy_rename_old_friendly_name_never_use_this'} = 1;
    $args->{'friendly_name'}                                        = delete $args->{'host'};
    my $result = Cpanel::API::wrap_deprecated( "SSL", "upload_cert", $args );
    return $result->status();
}

## DEPRECATED!
sub SSL_deletecrt {
    my ($host) = @_;

    _init();

    my $sslstorage = Cpanel::SSLStorage::User->new();
    my ( $ok, $certs ) = $sslstorage->find_certificates( 'friendly_name' => $host );
    return if !$ok || !@$certs;

    my $result = Cpanel::API::wrap_deprecated( "SSL", "delete_cert", { id => $certs->[0]{'id'} } );
    return $result->status();
}

##################################################
## cpdev: CABUNDLE

## DEPRECATED!
sub api2_fetchcabundle {
    my %CFG    = @_;
    my $crt    = $CFG{'crt'} || $Cpanel::FORM{'crt'};
    my $result = Cpanel::API::wrap_deprecated( "SSL", "get_cabundle", { cert => $crt, 'api.quiet' => 1 } );
    ## returns a hashref
    return $result->data();
}

## DEPRECATED, with maximum prejudice. Use ::API::get_cabundle, or less preferably
##   the above api2_fetchcabundle
sub SSL_getcabundle {
    my ( $domain, $crtdata ) = @_;
    _init();
    return Cpanel::SSLInfo::getcabundle( $domain, $crtdata, 1 );
}

##################################################
## cpdev: INSTALLATION

## DEPRECATED!
#NOTE: This function works completely differently from its UAPI counterpart
#since it bases its searches etc. off of the friendly_name.
sub api2_listsslitems {
    my %CFG = @_;

    my ( $domains, $items ) = @CFG{ 'domains', 'items' };

    return [] if !$items || !$domains;

    _init();

    my @items_list   = split m{\|}, $items;
    my @domains_list = sort split m{\|}, $domains;

    my %listers = (
        'key' => 'find_keys',
        'csr' => 'find_csrs',
        'crt' => 'find_certificates',
    );

    my $sslstorage = eval { Cpanel::SSLStorage::User->new() };
    if ( !$sslstorage ) {
        $Cpanel::CPERROR{'ssl'} = $@;
        return;
    }

    my @results;

    for my $type (@items_list) {
        my $lister = $listers{$type};
        next if !$lister;

        for my $domain (@domains_list) {
            my ( $ok, $items ) = $sslstorage->$lister( friendly_name => $domain );
            if ( $ok && @$items ) {
                push @results, { 'type' => $type, 'host' => $domain };
            }
        }
    }

    return @results;
}

#
#  SSL_getcnname
#
#  $domain can be a DOMAIN, USER, or EMAIL ADDRESS
#  this eventually gets passed to Cpanel::SSL::Domain::get_best_ssldomain_for_object
#  which knows about this legacy quirk and can handle it
#
#  We have to support them all for legacy reasons as this argument gets fed from getcnname
#  Example Legacy Usage:
#  <li><cptext 'SSL Incoming Mail Server'>: <strong><cpanel SSL="getcnname($RAW_FORM{'acct'},'imap')"></strong></li>
#
## DEPRECATED!
sub SSL_getcnname {
    my ( $domain, $service, $prevent_adding_mail_subdomain ) = @_;
    my $result = Cpanel::API::wrap_deprecated( "SSL", "get_cn_name", { domain => $domain, service => $service, 'add_mail_subdomain' => ( $prevent_adding_mail_subdomain ? 0 : 1 ) } );
    print $result->data()->{'ssldomain'};
}

#
#  api2_getcnname
#
#  $domain can be a DOMAIN, USER, or EMAIL ADDRESS
#  this eventually gets passed to Cpanel::SSL::Domain::get_best_ssldomain_for_object
#  which knows about this legacy quirk and can handle it
#
#  We have to support them all for legacy reasons as this argument gets fed from getcnname
#  Example Legacy Usage:
#  <li><cptext 'SSL Incoming Mail Server'>: <strong><cpanel SSL="getcnname($RAW_FORM{'acct'},'imap')"></strong></li>
#
## DEPRECATED!
sub api2_getcnname {
    my %CFG    = ( @_, 'api.quiet' => 1 );
    my $result = Cpanel::API::wrap_deprecated( "SSL", "get_cn_name", \%CFG );
    return $result->data();
}

#This preserves compatibility with pre-UAPI SSL installs.
#It returns a "rollback" method that can undo what has been done,
#or empty/undef on failure.
sub _save_cert_and_key_before_install {
    my ( $domain, $cert, $key ) = @_;

    _init();

    my @rollbacks;
    my $rollback_cr = sub {
        $_->() for reverse splice @rollbacks;
        return;
    };

    #Run the API call, and error out if we fail.
    my $uapi_ssl_cr = sub {
        my $response = Cpanel::API::execute( 'SSL', @_ );
        if ( !$response->status() ) {
            $Cpanel::CPERROR{'ssl'} = $response->errors_as_string();
            $rollback_cr->();
            return;
        }

        return $response;
    };

    do { s{\A\s+|\s+\z}{}g if defined }
      for ( $key, $cert );

    if ( !$domain ) {
        my ( $status, $ret ) = Cpanel::SSLInfo::getcrtdomain($cert);
        if ($status) {
            $domain = $ret;
        }
    }

    #If no key is given, see if the cert's key is already available.
    if ( !$key ) {
        my $find_key = $uapi_ssl_cr->( 'fetch_key_and_cabundle_for_certificate', { certificate => $cert } );
        if ( $find_key && $find_key->data() ) {
            $key = $find_key->data()->{'key'};
        }
    }

    #This will be dealt with in the actual install call.
    #Pass back success now so we actually try to install.
    return $rollback_cr if !$key || !$cert || !$domain;

    my @methods = (
        {
            list              => 'list_certs',
            del               => 'delete_cert',
            save              => 'upload_cert',
            save_params       => [ 'crt' => $cert ],
            set_friendly_name => 'set_cert_friendly_name',
            id_maker          => \&Cpanel::SSLStorage::Utils::make_certificate_id,
        },
        {
            list              => 'list_keys',
            del               => 'delete_key',
            save              => 'upload_key',
            save_params       => [ 'key' => $key ],
            set_friendly_name => 'set_key_friendly_name',
            id_maker          => \&Cpanel::SSLStorage::Utils::make_key_id,
        },
    );

    for my $methods_hr (@methods) {
        my ( $id_ok, $id ) = $methods_hr->{'id_maker'}->( $methods_hr->{'save_params'}[1] );
        if ( !$id_ok ) {
            $Cpanel::CPERROR{'ssl'} = $id;
            $rollback_cr->();
            return;
        }

        my $delete_function_name = $methods_hr->{'del'};
        my $setter_function_name = $methods_hr->{'set_friendly_name'};

        my $already_saved = $uapi_ssl_cr->(
            $methods_hr->{'list'},
            {
                'api.filter_column_0' => 'id',
                'api.filter_type_0'   => 'eq',
                'api.filter_term_0'   => $id,
            },
        );
        return if !$already_saved;    #an error

        $already_saved = $already_saved->data();

        if ( $already_saved && @$already_saved ) {

            #If the thingie is already installed with the correct friendly_name,
            #then we're done with this thingie.
            next if $already_saved->[0]{'friendly_name'} eq $domain;

            #We're actually going to *delete* the thingie if it's already saved.
            #That way, we'll just re-save it with the correct friendly_name,
            #using SSLStorage's internal rename-on-save logic.
            my $delete = $uapi_ssl_cr->(
                $delete_function_name,
                {
                    id => $id,
                }
            );
            return if !$delete;

            push @rollbacks, sub {
                my $result = Cpanel::API::execute(
                    'SSL',
                    $methods_hr->{'save'},
                    {
                        @{ $methods_hr->{'save_params'} },
                        friendly_name => $already_saved->[0]{'friendly_name'},
                    },
                );
                if ( !$result->status() ) {
                    Cpanel::Debug::log_warn( "SSL re-add fail: " . $result->errors_as_string() );
                }
            };
        }

        my $already_using_friendly_name = $uapi_ssl_cr->(
            $methods_hr->{'list'},
            {
                'api.filter_column_0' => 'friendly_name',
                'api.filter_type_0'   => 'eq',
                'api.filter_term_0'   => $domain,
            }
        );
        return if !$already_using_friendly_name;

        my $save = $uapi_ssl_cr->(
            $methods_hr->{'save'},
            {
                _api2_legacy_rename_old_friendly_name_never_use_this => 1,
                @{ $methods_hr->{'save_params'} },
                friendly_name => $domain,
            }
        );
        return if !$save;

        #If we changed anything's friendly_name, change it back on rollback.
        #NOTE: It's important to add this rollback *first* because the rename
        #of the old item happened *first* (i.e., before saving the new one).
        #This way, if the rollback is triggered, the new one will be deleted
        #before restoring the old friendly_name.
        my $already_ar = $already_using_friendly_name->data();
        if ( $already_ar && @$already_ar ) {
            push @rollbacks, sub {
                my $result = Cpanel::API::execute(
                    'SSL',
                    $setter_function_name,
                    {
                        id                => $already_ar->[0]{'id'},
                        new_friendly_name => $domain,
                    }
                );
                if ( !$result->status() ) {
                    Cpanel::Debug::log_warn( "SSL rename fail: " . $result->errors_as_string() );
                }
            };
        }

        #See above. In a real rollback, this happens *first*.
        push @rollbacks, sub {
            my $result = Cpanel::API::execute(
                'SSL',
                $delete_function_name,
                {
                    id => $save->data()->[0]{'id'},
                }
            );
            if ( !$result->status() ) {
                Cpanel::Debug::log_warn( "SSL delete fail: " . $result->errors_as_string() );
            }
        };
    }

    return $rollback_cr;
}

## DEPRECATED!
sub api2_installssl {
    my %CFG = ( @_, 'api.quiet' => 1 );
    $CFG{'cert'} = $CFG{'crt'};    ## attribute rename

    my $rollback_cr = _save_cert_and_key_before_install( @CFG{qw(domain  cert  key)} );
    return if !$rollback_cr;

    my $result = Cpanel::API::wrap_deprecated( 'SSL', 'install_ssl', \%CFG );

    if ( !$result->status() ) {
        $rollback_cr->();
    }

    my $output = $result->status() ? $result->messages_as_string() : $result->errors_as_string();
    return { result => $result->status(), output => $output };
}

## DEPRECATED!
sub SSL_install {
    my ( $domain, $cert, $key, $cabundle ) = @_;

    my $rollback_cr = _save_cert_and_key_before_install( $domain, $cert, $key );

    my $result = Cpanel::API::wrap_deprecated(
        "SSL",
        "install_ssl",
        {
            domain   => $domain,
            cert     => $cert,
            key      => $key,
            cabundle => $cabundle
        }
    );

    if ( !$result->status() ) {
        $rollback_cr->();
    }

    return $result->status();
}

## DEPRECATED, with maximum prejudice
sub SSL_installedhost {
    my ($domain) = @_;
    my $result   = Cpanel::API::wrap_deprecated( "SSL", "installed_host", { domain => $domain } );
    my $data     = $result->data();

    ## note: the "getdomainr" Javascript function created below used by x/ssl/installsslmain.html;
    ##   consider this clause extremely legacy
    if ( exists $data->{'host'} ) {
        my $host = $data->{'host'};
        $Cpanel::CPVAR{'sslhost'} = $host;
        my $aliases = '';
        if ( exists $data->{'aliases'} ) {
            $aliases = sprintf( ' (%s)', join( ' ', @{ $data->{'aliases'} } ) );
        }
        print qq(
$host $aliases
<script>
function getdomainr() {
    for(var i=0;i<document.mainform.domain.options.length;i++) {
    if (document.mainform.domain.options[i].value == "$host") {
        document.mainform.domain.selectedIndex = i;
    }
    }
    document.mainform.domain.disabled = true;
    lookupinfo();
}
</script>\n);
    }
    else {
        print "(none)\n";
        print "<script>function getdomainr() {}</script>\n";
    }
    return;
}

## DEPRECATED!
sub SSL_delete {
    my ($domain) = @_;
    print " ";    #needed for a work around with spacing
    my $result = Cpanel::API::wrap_deprecated( "SSL", "delete_ssl", { domain => $domain } );
    return $result->status();
}

##################################################

#Prior to 11.36, a key was named by the domain for which it was intended.
#In 11.36, this changes to Cpanel::SSLStorage, which doesn't associate a key
#with a domain.
#
#For backward compatibility, API2 calls set a key's 'friendly_name' attribute
#to the 'host' parameter passed in, and so we identify the key for certificate
#or CSR generation by that 'friendly_name'.
#
#Sets $Cpanel::CPERROR{'ssl'} and returns empty on error.
sub _find_key_id_for_domain {
    my $domain = shift;

    _init();
    my $sslstorage = eval { Cpanel::SSLStorage::User->new() } or do {
        $Cpanel::CPERROR{'ssl'} = $@;
        return;
    };

    my ( $ok, $keys ) = $sslstorage->find_keys( friendly_name => $domain );
    if ( !$ok ) {
        $Cpanel::CPERROR{'ssl'} = $keys;
        return;
    }
    elsif ( !$keys ) {
        eval 'require Cpanel::Locale' if !$INC{'Cpanel/Locale.pm'};
        $Cpanel::CPERROR{'ssl'} = Cpanel::Locale->get_handle()->maketext('There are no keys that match the given domain.');
        return;
    }

    #friendly_name is guaranteed to be unique.
    return $keys->[0]{'id'};
}

sub _lister {
    my $type = shift;

    my %method = (
        key         => 'list_keys',
        certificate => 'list_certs',
        csr         => 'list_csrs',
    );

    my $result = Cpanel::API::wrap_deprecated( "SSL", $method{$type}, { 'api.quiet' => 1 } );
    my $data   = $result->data();

    return if !$data;

    $data = [$data] if 'ARRAY' ne ref $data;    #just in case

    #A list of sorted, whitespace-stripped friendly_name's
    my @items = sort map { my $fname = $_->{'friendly_name'}; $fname =~ tr{ }{} ? () : $fname } @$data;

    return \@items;
}

my $sslinstall_feature_allow_demo = {
    needs_role    => 'UserSSL',
    needs_feature => 'sslinstall',
    allow_demo    => 1,
};

my $sslinstall_feature_deny_demo = {
    needs_role    => 'UserSSL',
    needs_feature => 'sslinstall',
};

my $sslmanager_feature_allow_demo = {
    needs_role    => 'UserSSL',
    needs_feature => 'sslmanager',
    allow_demo    => 1,
};

my $sslmanager_feature_deny_demo = {
    needs_role    => 'UserSSL',
    needs_feature => 'sslmanager',
};

our %API = (
    listcrts      => $sslmanager_feature_allow_demo,    # Wraps Cpanel::API::SSL::list_certs
    listcsrs      => $sslmanager_feature_allow_demo,    # Wraps Cpanel::API::SSL::list_csrs
    listsslitems  => $sslmanager_feature_allow_demo,
    fetchcabundle => $sslinstall_feature_allow_demo,    # Wraps Cpanel::API::SSL::get_cabundle
    listkeys      => $sslmanager_feature_allow_demo,    # Wraps Cpanel::API::SSL::list_keys
    genkey        => $sslmanager_feature_deny_demo,     # Wraps Cpanel::API::SSL::generate_key
    gencsr        => $sslmanager_feature_deny_demo,     # Wraps Cpanel::API::SSL::generate_csr
    gencrt        => $sslmanager_feature_deny_demo,     # Wraps Cpanel::API::SSL::generate_cert
    uploadkey     => $sslmanager_feature_deny_demo,     # Wraps Cpanel::API::SSL::upload_key
    uploadcrt     => $sslmanager_feature_deny_demo,     # Wraps Cpanel::API::SSL::upload_cert
    installssl    => $sslinstall_feature_deny_demo,     # Wraps Cpanel::API::SSL::install_ssl
    getcnname     => { allow_demo => 1 },               # Wraps Cpanel::API::SSL::get_cn_name
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
