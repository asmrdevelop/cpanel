package Cpanel::SSL::VhostCheck;

# cpanel - Cpanel/SSL/VhostCheck.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Config::WebVhosts    ();
use Cpanel::Context              ();
use Cpanel::Exception            ();
use Cpanel::LoadModule           ();
use Cpanel::SSL::CheckCommon     ();
use Cpanel::SSL::Verify          ();
use Cpanel::Apache::TLS          ();
use Cpanel::WebVhosts            ();
use Cpanel::WildcardDomain::Tiny ();

#----------------------------------------------------------------------
#Overridden in tests for mocking
*_list_vhosts = \&Cpanel::WebVhosts::list_vhosts;

our $_CERTIFICATE_FILE_CLASS = 'Cpanel::SSL::Objects::Certificate::File';

#TODO FIXME make this configurable?
our $MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED = 3;

my $sslverify;

#----------------------------------------------------------------------

#Returns a list of hashes, one for each vhost, each of which looks like:
#   {
#       vhost_name => ...,
#
#       domains    => vhost’s domains, sorted by:
#           - secured domains first
#           - shortest domains first
#           - lexicographical sort
#
#       problems   => array ref, any of:
#           NO_SSL
#           EMPTY_CERTIFICATE:(path)   - probably means something else is wrong!
#           MISSING_CERTIFICATE:(path) - ditto; certs should never be empty/missing.
#           NOT_ALL_DOMAINS
#           OCSP_REVOKED
#           WEAK_KEY
#           WEAK_SIGNATURE
#           ALMOST_EXPIRED
#           CA_CERTIFICATE_ALMOST_EXPIRED
#           OPENSSL_VERIFY:(depth):(error code):(error name)
#               see: https://www.openssl.org/docs/manmaster/apps/verify.html
#
#       certificate      => Cpanel::SSL::Objects::Certificate object
#
#       unsecured_domains => array ref
#   }
#
sub get_report_for_user {
    my ($username) = @_;

    Cpanel::Context::must_be_list();

    my %vh_unsecured_domains;

    my $vhconf = Cpanel::Config::WebVhosts->load($username);

    my @vhosts = _list_vhosts( $username, $vhconf );

    my %vh_domains = map {
        $_->{'vhost_name'} => [
            ( grep { !( index( $_, 'www.' ) == 0 && Cpanel::WildcardDomain::Tiny::contains_wildcard_domain($_) ) } @{ $_->{'domains'} } ),
            @{ $_->{'proxy_subdomains'} || [] },
        ]
    } @vhosts;

    my %has_ssl;
    $has_ssl{ $_->{'vhost_name'} } ||= $_->{'vhost_is_ssl'} for @vhosts;

    my @return;

    my %verify_cache;
    my %revoked_cache;
  VHNAME:
    for my $vhname ( sort keys %vh_domains ) {
        my @problems;
        my $cache_key;
        my $cert_obj;

        if ( $has_ssl{$vhname} ) {
            my $ud_domain = _vhname_to_userdata_domain($vhname);

            my $certs_file = Cpanel::Apache::TLS->get_certificates_path($ud_domain);

            if ( -s $certs_file ) {
                Cpanel::LoadModule::load_perl_module($_CERTIFICATE_FILE_CLASS);

                my ( $verify, @cab );

                try {
                    $cert_obj = $_CERTIFICATE_FILE_CLASS->new( path => $certs_file );

                    push @problems, _check_cert_for_internal_issues($cert_obj);

                    $sslverify ||= Cpanel::SSL::Verify->new();

                    @cab = $cert_obj->get_extra_certificates();

                    $cache_key = join( "\n", $cert_obj->text(), @cab );
                    $verify    = ( $verify_cache{$cache_key} ||= $sslverify->verify( $cert_obj->text(), @cab ) );
                }
                catch {
                    warn "Invalid certificate chain found at “$certs_file”! This should not normally happen--possible corruption!\n" . Cpanel::Exception::get_string($_);
                    push @problems, "INVALID_CERTIFICATE:$certs_file"
                };

                if ($cert_obj) {
                    if ($verify) {
                        if ( $verify->ok() ) {
                            $revoked_cache{$cache_key} //= _check_revocation( $cert_obj, @cab ) || 0;
                            push @problems, $revoked_cache{$cache_key} if $revoked_cache{$cache_key};
                        }
                        else {
                            push @problems, Cpanel::SSL::CheckCommon::get_problems_from_verify_result($verify);
                        }
                    }

                    my $secured_domains_ar = $cert_obj->find_domains_lists_matches( $vh_domains{$vhname} );

                    my %secured_domains_lookup;
                    @secured_domains_lookup{@$secured_domains_ar} = ();

                    $vh_unsecured_domains{$vhname} = [ grep { !exists $secured_domains_lookup{$_} } @{ $vh_domains{$vhname} } ];

                    if ( @{ $vh_unsecured_domains{$vhname} } ) {
                        push @problems, 'NOT_ALL_DOMAINS';
                    }
                }
            }
            else {
                my $prob = -e _ ? 'EMPTY_CERTIFICATE' : 'MISSING_CERTIFICATE';
                push @problems, "$prob:$certs_file";
            }
        }
        else {
            push @problems, 'NO_SSL';

            #We have no SSL vhost to rely on in this case, so we have to
            #fetch the SSL service (formerly proxy) subdomains data ourselves.
            my @proxy_subs = _load_proxy_subs_list( $vhconf, $vhname );
            push @{ $vh_domains{$vhname} }, @proxy_subs;
        }

        my $to_replace_yn = grep { !_problem_is_acceptable($_) } @problems;

        if ($cert_obj) {
            my @exp_problems = Cpanel::SSL::CheckCommon::get_expiration_problems( $cert_obj, $MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED );

            if (@exp_problems) {
                $to_replace_yn += 1;
                push @problems, @exp_problems;
            }
        }
        else {
            $vh_unsecured_domains{$vhname} = $vh_domains{$vhname};
        }

        my %unsecured_lookup;
        @unsecured_lookup{ @{ $vh_unsecured_domains{$vhname} } } = ();

        push @return, {
            vhost_name             => $vhname,
            should_install_new_ssl => $to_replace_yn,
            problems               => \@problems,
            certificate            => $cert_obj,
            unsecured_domains      => $vh_unsecured_domains{$vhname},

            #Sort order is defined as analogous to (pseudo-SQL):
            #   ORDER BY is_already_secured DESC, length(name), name
            #
            domains => [
                sort { ( exists( $unsecured_lookup{$a} ) cmp exists( $unsecured_lookup{$b} ) ) || ( length($a) <=> length($b) ) || $a cmp $b } @{ $vh_domains{$vhname} },
            ],
        };
    }

    return @return;
}

#overwritten in tests
sub _load_proxy_subs_list {
    my ( $vhconf, $vhname ) = @_;

    return $vhconf->ssl_proxy_subdomains_for_vhost($vhname);
}

sub _check_revocation {
    my ( $cert_obj, @cab ) = @_;

    if ( $cert_obj->revoked( join "\n", @cab ) ) {
        return 'OCSP_REVOKED';
    }

    return;
}

#This logic might be sensible to move out of the module,
#but there are other “problems” with certs that this doesn’t detect
#that depend on external factors (e.g., the CA bundle).
sub _check_cert_for_internal_issues {
    my ($cert_obj) = @_;

    my @problems;

    if ( !$cert_obj->key_is_strong_enough() ) {
        push @problems, 'WEAK_KEY';
    }

    if ( !$cert_obj->signature_algorithm_is_strong_enough() ) {
        push @problems, 'WEAK_SIGNATURE';
    }

    return @problems;
}

#This is currently trivial logic; however, vhost names need not always
#necessarily be the same as the userdata-indexed domain.
sub _vhname_to_userdata_domain {
    my ($vhname) = @_;
    return $vhname;
}

sub _problem_is_acceptable {
    my ($p) = @_;
    return $p eq 'NOT_ALL_DOMAINS';
}

END {
    undef $sslverify;
}

1;
