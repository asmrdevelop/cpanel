package Cpanel::SSL::Domain;

# cpanel - Cpanel/SSL/Domain.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Domain::TLS          ();
use Cpanel::Domain::Mail         ();
use Cpanel::LoadFile             ();
use Cpanel::LoadModule           ();
use Cpanel::Hostname             ();
use Cpanel::WildcardDomain       ();
use Cpanel::WildcardDomain::Tiny ();
use Cpanel::Exception            ();
my $logger;

our $SELF_SIGNED                    = 0;
our $SIGNED_WITH_MATCHING_DOMAIN    = 1;
our $SIGNED_WITHOUT_MATCHING_DOMAIN = 2;

#########################################################################
#
# Method:
#   get_certificate_assets_for_service
#
# Description:
#   Fetch the the certificate, key, and optional cabundle for a domain
#   on the specified service.
#
# Parameters:
#
#   domain            - The domain that you want to use
#   (required)          the installed key and certificate from
#                       to create the signature.
#
#   service           - The name of the service you want to use
#   (required)          the installed key and certificate from
#                       to create the signature if a certificate
#                       and key for the domain is not installed.
#
# Returns:
#   The signed payload
#

sub get_certificate_assets_for_service {
    my (%OPTS) = @_;

    foreach my $required (qw(service domain)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !length $OPTS{$required};
    }

    my $service = $OPTS{'service'};
    my $domain  = $OPTS{'domain'};

    my $cab;
    my ( $key, $crt, @cabs ) = Cpanel::Domain::TLS->get_tls($domain);
    $cab = join( "\n", @cabs ) if @cabs;

    if ( !$key || !$crt ) {
        require Cpanel::SSLCerts;

        #Ugh. This function is inconsistent as to its return context.
        #See CPANEL-8367.
        my $fetch_ssl_files_ref;
        my ( $ret, $err ) = Cpanel::SSLCerts::fetchSSLFiles( 'service' => $service );
        if ($ret) {
            $fetch_ssl_files_ref = $ret;
        }
        else {
            die $err || "Unknown failure to fetch default SSL resources for “$service”!";
        }

        $key = $fetch_ssl_files_ref->{'key'};
        $crt = $fetch_ssl_files_ref->{'crt'};
        $cab = $fetch_ssl_files_ref->{'cab'};

        if ( !$key || !$crt ) {
            die Cpanel::Exception->create( 'The system could not fetch the certificate for the “[_1]” domain, or the certificate configured for the “[_2]” service.', [ $domain, $service ] );
        }
    }

    return {
        'certificate' => $crt,
        'key'         => $key,
        'cabundle'    => $cab,
    };
}

#
#  $object can be a DOMAIN, USER, or EMAIL ADDRESS
#
#  We have to support them all for legacy reasons as this argument gets fed from getcnname
#  Example Legacy Usage:
#  <li><cptext 'SSL Incoming Mail Server'>: <strong><cpanel SSL="getcnname($RAW_FORM{'acct'},'imap')"></strong></li>
#
#   $opts can be:
#       service     (as given by Cpanel::SSL::ServiceMap::lookup_service_group())
#       add_mail_subdomain - for mail services
#
sub get_best_ssldomain_for_object {
    my ( $object, $opts ) = @_;

    my $service            = $opts->{'service'};
    my $add_mail_subdomain = $opts->{'add_mail_subdomain'} ? 1 : 0;
    #
    #  $object can be a DOMAIN, USER, or EMAIL ADDRESS
    #  _get_domain_from_object will make sure we are working with a domain
    #
    my $domain = _get_domain_from_object( $object, $opts );

    my $ssldomain;
    my $is_self_signed         = 1;
    my $cert_match_method      = 'none';
    my $is_wild_card_match     = 0;
    my $ssldomain_matches_cert = 0;
    my $cert_valid_not_after;

    $add_mail_subdomain &&= !Cpanel::Domain::Mail::is_mail_subdomain($domain);

    my $mail_subdomain;
    my $mail_subdomain_exists;

    if ($service) {
        my ( $service_cert_info, $now );

        my @domains = ($domain);

        #Prioritize the mail subdomain when it’s requested.
        if ($add_mail_subdomain) {
            $mail_subdomain ||= Cpanel::Domain::Mail::make_mail_subdomain($domain);
            $mail_subdomain_exists //= Cpanel::Domain::Mail::mail_subdomain_exists($domain);

            if ($mail_subdomain_exists) {
                unshift @domains, Cpanel::WildcardDomain::to_wildcards($mail_subdomain);    # Check wildcards.
                if ( $mail_subdomain ne $domain ) {
                    unshift @domains, $mail_subdomain;
                }
            }
        }

        try {
            require Cpanel::Domain::TLS;

          DOMAIN:
            for my $this_d (@domains) {
                my ($c_path) = Cpanel::Domain::TLS->get_certificates_path($this_d);
                if ( -e $c_path ) {
                    $ssldomain = $this_d;
                    $ssldomain =~ s<\A[*]><mail>;

                    my $c_obj = _get_cpanel_ssl_objects_certificate_cached($c_path);

                    if ( $c_obj && !$c_obj->is_self_signed() && ( $c_obj->not_after() // 0 ) > ( $now // time() ) ) {
                        $service_cert_info = {
                            is_self_signed => 0,
                            certdomains    => $c_obj->domains(),
                            not_after      => $c_obj->not_after(),
                        };
                    }

                    last DOMAIN;
                }
            }
        }
        catch {
            warn "Failed to load and parse TLS resources for the domain “$domain”: $_";
        };

        if ( !$service_cert_info ) {

            # Fallback to the primary cert (usually the hostname)
            my ( $load_ok, $loaded_service_cert_info ) = load_service_certificate_info($service);

            if ($load_ok) {
                $service_cert_info = $loaded_service_cert_info;

                # our test cases assume we use the passed in domain
                # when we cannot get the domains off the cert
                if ( !$service_cert_info->{'certdomains'} || !@{ $service_cert_info->{'certdomains'} } ) {
                    $service_cert_info->{'certdomains'} = [$domain];
                }
            }
        }

        if ($service_cert_info) {
            $is_self_signed       = $service_cert_info->{'is_self_signed'};
            $cert_valid_not_after = $service_cert_info->{'not_after'};
            if ( my $match = _find_best_match_for_domain_on_certificate( $domain, $service_cert_info->{'certdomains'}, $opts ) ) {
                $ssldomain              = $match->{'ssldomain'};
                $is_wild_card_match     = $match->{'is_wild_card_match'};
                $ssldomain_matches_cert = $match->{'ssldomain_matches_cert'};
                $cert_match_method      = $match->{'cert_match_method'};
            }
        }
    }

    #
    # If nothing matches the domain then we fallback
    # and go to the domain even though we know the cert
    # will not match
    #
    if ( !$ssldomain ) {

        if ( $add_mail_subdomain && !Cpanel::Domain::Mail::is_mail_subdomain($domain) ) {
            $mail_subdomain_exists //= Cpanel::Domain::Mail::mail_subdomain_exists($domain);
            if ($mail_subdomain_exists) {
                $mail_subdomain ||= Cpanel::Domain::Mail::make_mail_subdomain($domain);
                $ssldomain = $mail_subdomain;
            }
        }

        $ssldomain ||= $domain;
    }

    # for legacy
    # reasons as many systems do not check
    # the newer ssldomain_matches_cert variable
    # and can only decide if the domain is on the cert
    # from the is_self_signed variable
    #
    # We always set is_self_signed to a true value
    # if ssldomain_matches_cert is not true
    #
    if ( !$ssldomain_matches_cert ) {
        $is_self_signed = $SIGNED_WITHOUT_MATCHING_DOMAIN;
    }

    return (
        1,
        {
            'ssldomain'              => $ssldomain,
            'is_self_signed'         => $is_self_signed,
            'is_wild_card'           => $is_wild_card_match,
            'ssldomain_matches_cert' => $ssldomain_matches_cert,
            'cert_match_method'      => $cert_match_method,
            'cert_valid_not_after'   => $cert_valid_not_after,
            'is_currently_valid'     => ( !$is_self_signed && $ssldomain_matches_cert && ( $cert_valid_not_after && $cert_valid_not_after > time() ) ) ? 1 : 0,
        }
    );
}

# Gets the best ssldomain for a supplied service.
# See get_best_ssldomain_for_object for service names.
sub get_best_ssldomain_for_service {
    my ($service) = @_;

    my ( $ssl_domain_info_status, $ssl_domain_info ) = get_best_ssldomain_for_object( Cpanel::Hostname::gethostname(), { 'service' => $service } );
    if ( $ssl_domain_info_status && $ssl_domain_info->{'ssldomain'} ) {
        return $ssl_domain_info->{'ssldomain'};
    }

    return Cpanel::Hostname::gethostname();
}

sub _find_best_match_for_domain_on_certificate {
    my ( $domain, $certdomains_ref, $opts ) = @_;

    my @lowercase_certdomains = map { my $domain = $_; $domain =~ tr{A-Z}{a-z}; $domain } @{$certdomains_ref};

    my $add_mail_subdomain = $opts->{'add_mail_subdomain'} ? 1 : 0;
    my @test_domains       = ($domain);
    if ( $add_mail_subdomain && !Cpanel::Domain::Mail::is_mail_subdomain($domain) && Cpanel::Domain::Mail::mail_subdomain_exists($domain) ) {
        @test_domains = ( Cpanel::Domain::Mail::make_mail_subdomain($domain), $domain );
    }

    my @wildcard_certdomains = grep { Cpanel::WildcardDomain::Tiny::is_wildcard_domain($_) } @lowercase_certdomains;

    foreach my $test_domain (@test_domains) {

        # First look for an exact match
        if ( my @matching_domains = grep { $_ eq $test_domain && !Cpanel::WildcardDomain::Tiny::is_wildcard_domain($test_domain) } @lowercase_certdomains ) {

            return {
                'is_wild_card_match'     => 0,
                'ssldomain'              => $matching_domains[0],
                'ssldomain_matches_cert' => 1,
                'cert_match_method'      => 'exact'
            };

        }

        #
        # Check for wildcard matches first
        #
        foreach my $cert_domain (@wildcard_certdomains) {
            if ( Cpanel::WildcardDomain::wildcard_domains_match( $cert_domain, $test_domain ) ) {

                return {
                    'is_wild_card_match'     => 1,
                    'ssldomain'              => $test_domain,
                    'ssldomain_matches_cert' => 1,
                    'cert_match_method'      => ( Cpanel::Domain::Mail::is_mail_subdomain($test_domain) ? 'mail-wildcard' : 'exact-wildcard' )
                };

            }
        }
    }

    #
    #  Now try www.domain or mail.domain against the wildcards
    #  If the root domain matches the wildcard without the *,
    # we prepend www, or mail depending on the setting of
    # add_mail_subdomain
    #
    foreach my $cert_domain (@wildcard_certdomains) {
        if ( Cpanel::WildcardDomain::wildcard_domains_match( $cert_domain, 'www.' . $domain ) ) {
            return {
                'is_wild_card_match'     => 1,
                'ssldomain'              => 'www.' . $domain,
                'ssldomain_matches_cert' => 1,
                'cert_match_method'      => 'www-wildcard'
            };

        }
    }

    #
    # If that failed and the hostname is on the cert then use it
    #
    my $hostname = Cpanel::Hostname::gethostname();
    foreach my $cert_domain (@lowercase_certdomains) {
        if ( Cpanel::WildcardDomain::wildcard_domains_match( $cert_domain, $hostname ) ) {    # will exact match as well
            my $is_wild_card_match = Cpanel::WildcardDomain::Tiny::is_wildcard_domain($cert_domain) ? 1 : 0;
            return {
                'is_wild_card_match'     => $is_wild_card_match,
                'ssldomain'              => $hostname,
                'ssldomain_matches_cert' => 1,
                'cert_match_method'      => ( $is_wild_card_match ? 'hostname-wildcard' : 'hostname' )
            };
        }
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Domain::Local');
    my $prefix = ( $add_mail_subdomain ? 'mail' : 'www' );
    #
    # Now try to use any domain on the cert that is on the server
    #
    foreach my $cert_domain (@lowercase_certdomains) {
        if ( Cpanel::WildcardDomain::Tiny::is_wildcard_domain($cert_domain) ) {
            my $test_domain = $cert_domain;
            substr( $test_domain, 0, 2, '' ) if index( $test_domain, '*.' ) == 0;
            if ( _domain_is_owned_or_local( $test_domain, $prefix . '.' . $test_domain ) ) {
                return {
                    'is_wild_card_match'     => 1,
                    'ssldomain'              => $prefix . '.' . $test_domain,
                    'ssldomain_matches_cert' => 1,
                    'cert_match_method'      => 'localdomain_on_cert-' . $prefix . '-wildcard'
                };

            }

        }
        elsif ( _domain_is_owned_or_local( $cert_domain, $cert_domain ) ) {
            return {
                'is_wild_card_match'     => 0,
                'ssldomain'              => $cert_domain,
                'ssldomain_matches_cert' => 1,
                'cert_match_method'      => 'localdomain_on_cert'
            };

        }
    }

    return;
}

sub _get_domain_from_object {
    my ($object) = @_;

    my $domain = $object;

    #
    # Convert email address to a domain
    #
    if ( $domain =~ /\@/ ) {
        $domain = ( split( /\@/, $domain ) )[1];
    }
    #
    # Convert a user to a domain
    #
    elsif ( $domain !~ tr/\.// ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::AcctUtils::Domain');
        if ( my $users_primary_domain = 'Cpanel::AcctUtils::Domain'->can('getdomain')->($domain) ) {
            $domain = $users_primary_domain;
        }
    }
    #
    # If we do not have a way to parse it
    # we just return it
    #
    else {
        $domain = $object;
    }

    $domain =~ tr{A-Z}{a-z};    # domain must be in lowercase characters

    return $domain;
}

my %cert_parse_cache;

sub _get_cpanel_ssl_objects_certificate_cached {
    my ($c_path) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::SSL::Objects::Certificate::File') if !$INC{'Cpanel/SSL/Objects/Certificate/File.pm'};
    $cert_parse_cache{$c_path} ||= Cpanel::SSL::Objects::Certificate::File->new( path => $c_path );
    return $cert_parse_cache{$c_path};
}

sub _domain_is_owned_or_local {
    my ( $domain_without_prefix, $domain_with_prefix ) = @_;

    # First we try the domain without the prefix to see if it has an owner
    # because this is a cheap lookup.  We check without the prefix
    # since its only important that they own the domain in question.
    require Cpanel::AcctUtils::DomainOwner::Tiny;
    return 1 if Cpanel::AcctUtils::DomainOwner::Tiny::domain_has_owner($domain_without_prefix);

    # If not we need to do DNS resolution which can cause the webmail
    # interface to block which is something we do not want to happen
    # and is only done as a last resort.  In this case we check WITH
    # the prefix since we are doing a DNS resolution for the exact domain.
    require Cpanel::Domain::Local;
    return 1 if Cpanel::Domain::Local::domain_or_ip_is_on_local_server($domain_with_prefix);
    return 0;
}

sub load_service_certificate_info {
    my $service = shift;

    if ( !$service ) {
        return ( 0, "load_service_certificate_info requires a service as the parameter" );
    }
    elsif ( $service =~ tr{/}{} ) {
        return ( 0, "load_service_certificate_info requires a valid service as the parameter" );
    }

    my $service_ssl_dir = '/var/cpanel/ssl/' . $service;

    my $signature_chain_verified_file_contents = Cpanel::LoadFile::loadfile("$service_ssl_dir-SIGNATURE_CHAIN_VERIFIED") || '';

    my $not_after_file_contents = Cpanel::LoadFile::loadfile("$service_ssl_dir-NOT_AFTER") || '';

    my $is_self_signed = ( $signature_chain_verified_file_contents =~ /(1)/ )[0] ? 0 : 1;

    my $not_after = ( $not_after_file_contents =~ /([0-9]+)/ )[0];

    my @certdomains = split( /\n/, Cpanel::LoadFile::loadfile("$service_ssl_dir-DOMAINS") || '' );

    return (
        1,
        {
            'is_self_signed' => $is_self_signed,
            'certdomains'    => \@certdomains,
            'not_after'      => $not_after
        }
    );
}

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::SSL::Domain - Utilities to determine the best domain for an ssl host, match wildcards, and read certificate info.

=head1 DESCRIPTION

This module includes general utility functions for use in finding the best domain for an ssl host,
matching wildcards, and reading certificate info.

=head2 Methods

=over 4

=item C<get_best_ssldomain_for_object>

When given a domain, email address, or username, this function will return the best ssl hostname to
connect to.

We defined best ssl hostname as one that is closest to the original domain and least likely to produce a ssl warning.

If a service parameter is provided, the installed certificate for the service will be examined in order to
provide the domain on the certificate that best matches the domain provided.

If the add_mail_subdomain parameter is provided, and multiple best ssl domains are found by the function,
the one that begins with mail. will be preferred.

=item C<load_service_certificate_info>

This function returns information about the certificate installed for a specific service.  It will
return the following keys: is_self_signed, certdomains, and not_after.

=back

=head1 SYNOPSIS

 use Cpanel::SSL::Domain ();

 my ( $ok, $ssl_domain_info ) = Cpanel::SSL::Domain::get_best_ssldomain_for_object( $domain,
            { 'service' => $service, 'add_mail_subdomain' => $add_mail_subdomain } );

 if ($ok) {
     my $ssldomain = $ssl_domain_info->{'ssldomain'};
     my $is_self_signed = $ssl_domain_info->{'is_self_signed'};
     my $is_wild_card = $ssl_domain_info->{'is_wild_card'};
     my $ssldomain_matches_cert = $ssl_domain_info->{'ssldomain_matches_cert'};
     my $cert_match_method = $ssl_domain_info->{'cert_match_method'};
     my $cert_valid_not_after = $ssl_domain_info->{'cert_valid_not_after'};
 }

 my ( $ok, $service_cert_info ) = load_service_certificate_info($service);
 if ($ok) {
     $is_self_signed       = $service_cert_info->{'is_self_signed'};
     $cert_valid_not_after = $service_cert_info->{'not_after'};
 }

=cut
