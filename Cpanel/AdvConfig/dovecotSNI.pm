package Cpanel::AdvConfig::dovecotSNI;

# cpanel - Cpanel/AdvConfig/dovecotSNI.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Domain::TLS                     ();
use Cpanel::PwCache::Build                  ();
use Cpanel::Exception                       ();
use Cpanel::AdvConfig::dovecot::utils       ();
use Cpanel::SSL::Objects::Certificate::File ();
use Cpanel::Config::LoadUserDomains         ();
use Cpanel::SSL::Utils                      ();
use Whostmgr::Email                         ();
use Cpanel::AdvConfig::dovecotSSL           ();
use Cpanel::SSL::Domain                     ();
use Cpanel::ConfigFiles                     ();

use Try::Tiny;

use base 'Cpanel::AdvConfig::dovecot::Includes';

our $VERSION = '2.0';

my $conf = {};

sub new ($pack) {
    return $pack->SUPER::new(
        {
            service       => 'dovecotSNI',
            verify_checks => [ 'multi local_name', 'explict maincert local_name' ],
            conf_file     => $Cpanel::ConfigFiles::DOVECOT_SNI_CONF,
        }
    );
}

sub get_config ( $self, $args_ref = undef ) {

    my $main_dovecotSSL_conf = Cpanel::AdvConfig::dovecotSSL->new()->get_config();

    # There's caching going on all over the place, so reset every global
    if ( exists $args_ref->{'reload'} && $args_ref->{'reload'} ) {
        $conf = {};
    }

    if ( $conf->{'_initialized'} ) {
        return wantarray ? ( 1, $conf ) : $conf;
    }

    my %domains_included;
    my %wildcard_domains_included;
    my $cert_domains;
    try {
        $cert_domains     = Cpanel::SSL::Objects::Certificate::File->new( path => $main_dovecotSSL_conf->{'ssl_cert_file'} )->domains();
        %domains_included = map { $_ => 1 } @$cert_domains;
        if ( my @wildcard_domains = grep { rindex( $_, '*', 0 ) == 0 } @$cert_domains ) {
            @wildcard_domains_included{@wildcard_domains} = (1) x scalar @wildcard_domains;
        }
    }
    catch {
        # These will be created later on a fresh install.
        $self->{logger}->warn( "The “$main_dovecotSSL_conf->{'ssl_cert_file'}” certificate fetch failed due to an error: " . Cpanel::Exception::get_string($_) ) unless $ENV{'CPANEL_BASE_INSTALL'};
    };

    my $trueuserdomains = Cpanel::Config::LoadUserDomains::loadtrueuserdomains();
    my $domains         = $self->_filter_domains_for_sni_config(
        {
            'domains'           => [ Cpanel::Domain::TLS->get_tls_domains() ],
            'trueuserdomains'   => $trueuserdomains,
            'included'          => \%domains_included,
            'wildcard_included' => \%wildcard_domains_included
        }
    );

    my $hard_defaults = {
        '_target_conf_file' => Cpanel::AdvConfig::dovecot::utils::find_dovecot_sni_conf(),
        'ssl_key_file'      => $main_dovecotSSL_conf->{'ssl_key_file'},
        'ssl_cert_file'     => $main_dovecotSSL_conf->{'ssl_cert_file'},

        # CPANEL-10582: Ensure that dovecot-lda never loads sni.conf
        # because it can take 6+ seconds on a machine with many certs
        # This can result in a massive mail delivery overhead.  By setting
        # the permissions to 0640 we allow dovecot to use it for imap
        # and pop ssl, and deprive dovecot-lda of the pain of loading it.
        #
        '_target_conf_perms' => 0640,

        'main_cert_domains' => $cert_domains,
        'mail_sni_domains'  => $domains,
        'get_domain_path'   => sub { Cpanel::Domain::TLS->get_tls_path(@_) },
    };

    %$conf = ( %$conf, %$hard_defaults );    # no need to use Cpanel::CPAN::Hash::Merge::merge since all keys are top level

    $conf->{'_initialized'} = 1;
    return wantarray ? ( 1, $conf ) : $conf;
}

sub _filter_domains_for_sni_config ( $self, $opts ) {

    my ( $domains_ar, $trueuserdomains, $domains_included_ref, $wildcard_domains_included_ref ) =
      ( $opts->{domains}, $opts->{trueuserdomains}, $opts->{included}, $opts->{wildcard_included} );

    my $dovecot_ssl_domain = Cpanel::SSL::Domain::get_best_ssldomain_for_service('dovecot');
    Cpanel::PwCache::Build::init_passwdless_pwcache();

    my $domain_to_user_map;
    my $cache_built;
    my %email_accounts_by_domain;
    my @local_name_entries;
    foreach ( sort @$domains_ar ) {
        my $domain = $_;
        my $non_mail_domain;
        $non_mail_domain = substr( $domain, 5 ) if rindex( $domain, 'mail.', 0 ) == 0;

        # don't add www. domains
        next if rindex( $domain, 'www.', 0 ) == 0;
        next if $domains_included_ref->{$domain};

        # We need to try both due to a bug adding mail. domains to /etc/userdomains CPANEL-9337
        if ( !$trueuserdomains->{$domain} && ( !length $non_mail_domain || !$trueuserdomains->{$non_mail_domain} ) ) {
            if ( !$cache_built ) {
                $domain_to_user_map = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );
                $cache_built        = 1;
            }
            my $domain_owner = $domain_to_user_map->{$domain} || '';

            # mail. is a special case, it can either be owned by a user or we automatically create it for a user who owns the parent domain
            if ( !length $domain_owner && length $non_mail_domain ) {
                $domain_owner = $domain_to_user_map->{$non_mail_domain} || '';
            }

            if ( length $domain_owner ) {
                try {
                    $email_accounts_by_domain{$domain}          //= Whostmgr::Email::count_pops_for_without_ownership_check( $domain_owner, $domain );
                    $email_accounts_by_domain{$non_mail_domain} //= Whostmgr::Email::count_pops_for_without_ownership_check( $domain_owner, $non_mail_domain ) if length $non_mail_domain;
                }
                catch {
                    $self->{logger}->warn( "The domain '$domain' owned by '$domain_owner' will not be added to the Dovecot SNI configuration because the system could not retrieve the email account count due to an error: " . Cpanel::Exception::get_string($_) );
                };

                # We're checking both here due to another bug that was adding mail. domains to /etc/userdomains CPANEL-9337
                # it's better to have a few extra mail. domains added to the sni config than NOT have them added at all
                next if !$email_accounts_by_domain{$domain} && ( !length $non_mail_domain || !$email_accounts_by_domain{$non_mail_domain} );
            }
            else {
                next if $domain ne $dovecot_ssl_domain && ( !length $non_mail_domain || $non_mail_domain ne $dovecot_ssl_domain );
            }
        }
        my $cert_domains;
        try {
            $cert_domains = Cpanel::SSL::Objects::Certificate::File->new( path => Cpanel::Domain::TLS->get_certificates_path($domain) )->domains();
        }
        catch {
            $self->{logger}->warn( "The tls domain '$domain' certificate fetch failed due to an error: " . Cpanel::Exception::get_string($_) );
        };

        if ( $cert_domains && ref $cert_domains ) {
            my @unseen_domains = grep { !$domains_included_ref->{$_} } @$cert_domains;
            if (@unseen_domains) {

                #Dovecot before 2.2.27 and later can support wildcards
                #so we no longer change the cert domains from * -> mail
                push @local_name_entries, { 'domain_tls' => $domain, 'cert_domains' => \@unseen_domains };

                @{$domains_included_ref}{@unseen_domains} = (1) x scalar @unseen_domains;

                if ( my @wildcard_domains = grep { rindex( $_, '*', 0 ) == 0 } @unseen_domains ) {
                    @{$wildcard_domains_included_ref}{@wildcard_domains} = (1) x scalar @wildcard_domains;
                }
            }
        }
    }

    _remove_domains_that_match_wildcards( \@local_name_entries, $wildcard_domains_included_ref );

    return \@local_name_entries;
}

sub _remove_domains_that_match_wildcards ( $local_entries, $wc_included ) {

    return 0 if !scalar keys %$wc_included;

    my @all_wildcard_domains = keys %$wc_included;
    my @wc_filtered_local_name_entries;

    foreach my $local_name_entry (@$local_entries) {
        my $remove_domains_ref = Cpanel::SSL::Utils::find_domains_lists_matches( [ grep { index( $_, '*' ) != 0 } @{ $local_name_entry->{'cert_domains'} } ], \@all_wildcard_domains );

        if ( $remove_domains_ref && @$remove_domains_ref ) {
            my %remove_domains_map = map  { $_ => 1 } @$remove_domains_ref;
            my @keep_domains       = grep { !$remove_domains_map{$_} } @{ $local_name_entry->{'cert_domains'} };
            if (@keep_domains) {
                push @wc_filtered_local_name_entries, { 'domain_tls' => $local_name_entry->{'domain_tls'}, 'cert_domains' => \@keep_domains };
            }

        }
        else {
            push @wc_filtered_local_name_entries, $local_name_entry;
        }

    }

    @$local_entries = @wc_filtered_local_name_entries;
    return 1;
}

# For testing
sub reset_cache {
    $conf = {};

    return;
}

1;
