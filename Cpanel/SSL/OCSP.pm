package Cpanel::SSL::OCSP;

# cpanel - Cpanel/SSL/OCSP.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Net::SSLeay ();

use Cpanel::Debug                    ();
use Cpanel::HTTP::Client             ();
use Cpanel::NetSSLeay                ();
use Cpanel::NetSSLeay::Constants     ();
use Cpanel::NetSSLeay::ErrorHandling ();
use Cpanel::NetSSLeay::CTX           ();
use Cpanel::NetSSLeay::BIO           ();
use Cpanel::NetSSLeay::SSL           ();
use Cpanel::NetSSLeay::X509          ();
use Cpanel::Try                      ();

our $TIMEOUT = 10;

use constant ACCEPTABLE_OCSP_ERRORS => qw(
  OCSP_R_STATUS_EXPIRED
  OCSP_R_STATUS_NOT_YET_VALID
  OCSP_R_STATUS_TOO_OLD
);

my $http;    # we tend to do a lot of these at once so try to keep alive

#Run an OCSP check on a certificate chain.
#The leaf certificate must be first.
#
#Responses from this are:
#   - undef: status unknown (caller should assume valid)
#   - 0: confirmed valid
#   - 1: revoked
#   - (1, $err_str): revoked, called in list context
#
#If an error occurs during verification, an exception will be thrown.
#
sub cert_chain_is_revoked {
    my ( $ocsp_uri, @cert_chain ) = @_;

    if ( !length $ocsp_uri ) {
        die "An OCSP URI is required.";
    }
    if ( !_sane_looking_http_uri($ocsp_uri) ) {
        die "“[_1]” is not a valid HTTP OCSP URI.";
    }
    if ( !@cert_chain ) {
        die "Give at least one certificate.";
    }
    if ( grep { !length } @cert_chain ) {
        die "Certificates cannot be empty. (@cert_chain)";
    }

    Net::SSLeay::initialize();
    my $ctx_obj    = Cpanel::NetSSLeay::CTX->new();
    my $ssl_obj    = Cpanel::NetSSLeay::SSL->new($ctx_obj);
    my $x509_store = $ctx_obj->get_cert_store();

    my $cert_to_check;
    foreach my $pem (@cert_chain) {
        my $bio_obj = Cpanel::NetSSLeay::BIO->new_s_mem();
        $bio_obj->write($pem);
        my $cert = Cpanel::NetSSLeay::do( 'PEM_read_bio_X509', $bio_obj->PTR() );
        $cert_to_check ||= $cert;

        $x509_store->add_cert( Cpanel::NetSSLeay::X509->new_wrap($cert) );
    }

    my $id           = Cpanel::NetSSLeay::do( 'OCSP_cert2ids', $ssl_obj->PTR(), $cert_to_check );
    my $ocsp_request = Cpanel::NetSSLeay::do( 'OCSP_ids2req',  $id );

    # We could extract from the cert but we already have it
    # my $uri = Net::SSLeay::P_X509_get_ocsp_uri($cert_to_check);
    # OCSP never uses HTTPs
    $http ||= Cpanel::HTTP::Client->new( verify_SSL => 0 );

    #Even though we’re just going to trap errors, we should still
    #create an exception because it gives us a nicely-formatted message.
    $http->die_on_http_error();

    my $content;

    my $attempt_http_cr = sub {
        my $response = $http->post(
            $ocsp_uri,
            {
                headers => { 'Content-type' => 'application/ocsp-request' },
                content => Net::SSLeay::i2d_OCSP_REQUEST($ocsp_request)
            }
        );

        $content = $response->content();
        if ( !length $content ) {
            Cpanel::Debug::log_warn("The OCSP response from “$ocsp_uri” was empty!");
        }
    };

    Cpanel::Try::try(
        $attempt_http_cr,

        'Cpanel::Exception::HTTP::Network' => sub {
            my $msg = $@->to_string();
            Cpanel::Debug::log_warn("Retrying after network failure: $msg");

            eval { $attempt_http_cr->(); 1 } or do {
                Cpanel::Debug::log_warn("$@");
            };
        },

        q<> => sub { Cpanel::Debug::log_warn("$@"); },
    );

    return undef if !length $content;

    # Extract OCSP_RESPONSE.
    # this will croak if the string is not an OCSP_RESPONSE
    my $parsed_ocsp_response = Cpanel::NetSSLeay::do( 'd2i_OCSP_RESPONSE', $content );

    # Check status of response.
    my $status = Cpanel::NetSSLeay::do( 'OCSP_response_status', $parsed_ocsp_response );
    if ( $status != Net::SSLeay::OCSP_RESPONSE_STATUS_SUCCESSFUL() ) {

        #We started getting lots of “unauthorized” once AutoSSL went live
        #as Comodo didn’t keep up with the need to have the OCSP service
        #know about a newly-issued certificate, so an installation that
        #followed hot on the heels of the cert’s issuance received this
        #response, which generally indicates that the OCSP server doesn’t
        #know about the certificate (i.e., the *server* isn’t “authorized”
        #to comment on the cert’s validity!).
        #
        #Rather than forward this on to the logs where it will create noise
        #and prompt spurious tickets, we just silently indicate unknown status
        #for the OCSP check.
        if ( $status != Net::SSLeay::OCSP_RESPONSE_STATUS_UNAUTHORIZED() ) {
            Cpanel::Debug::log_warn( "OCSP response from $ocsp_uri failed: " . Net::SSLeay::OCSP_response_status_str($status) );
        }

        return undef;
    }

    my $result;
    try {
        ($result) = Cpanel::NetSSLeay::do( 'OCSP_response_results', $parsed_ocsp_response, $id );
    }
    catch {
        my $ignore;
        if ( try { $_->isa('Cpanel::Exception::NetSSLeay') } ) {
            if ( 1 == @{ $_->get('error_codes') } ) {
                my $reason = Cpanel::NetSSLeay::ErrorHandling::ERR_GET_REASON( $_->get('error_codes')->[0] );
                if ( grep { $reason == Cpanel::NetSSLeay::Constants->$_() } ACCEPTABLE_OCSP_ERRORS() ) {
                    $ignore = 1;
                    Cpanel::Debug::log_warn( "The OCSP revocation check failed because of an error: " . $_->get_string_no_id() );
                    Cpanel::Debug::log_warn("This can sometimes be corrected by running: “rdate -s rdate.cpanel.net” or “ntpclient -s -h pool.ntp.org”.");
                }
            }
        }

        if ( !$ignore ) {
            local $@ = $_;
            die;
        }
    };

    if ($result) {
        my ( $cert_id, $err, $details ) = @{$result};

        if ( defined $details->{'statusType'} ) {
            if ( $details->{'statusType'} == Net::SSLeay::V_OCSP_CERTSTATUS_REVOKED() ) {
                return wantarray ? ( 1, $err ) : 1;
            }
            if ( $details->{'statusType'} == Net::SSLeay::V_OCSP_CERTSTATUS_GOOD() ) {
                return 0;
            }
        }
    }

    return undef;    # unknown status
}

#Like cert_chain_is_revoked(), but will fetch and order the CAB if needs be.
sub cert_is_revoked {
    my ( $cert_string, $ocsp_uri, $cab_pem ) = @_;

    if ( !$cert_string ) {
        die "cert_is_revoked requires a certificate in PEM format.";
    }

    my @cert_chain = ($cert_string);

    if ( !$cab_pem ) {
        require Cpanel::SSLInfo;
        my $cab = ( Cpanel::SSLInfo::fetchcabundle($cert_string) )[2];
        $cab_pem = $cab if Cpanel::SSLInfo::is_ssl_payload($cab);
    }

    if ($cab_pem) {
        require Cpanel::SSL::Objects::CABundle;
        my $cab_object = Cpanel::SSL::Objects::CABundle->new( 'cab' => $cab_pem );
        my ( $ok, $ordered_ar ) = $cab_object->get_chain_without_trusted_root_certs();

        push @cert_chain, map { $_->text() } @{$ordered_ar};
    }

    return cert_chain_is_revoked( $ocsp_uri, @cert_chain );
}

#Not intended to be a complete validation; just a quick sanity check.
#For more complete logic, maybe CPAN’s URI.pm module would do?
sub _sane_looking_http_uri {
    my ($uri) = @_;

    return 1 if $uri =~ m{^http://[A-Za-z0-9\.]+};
    return 0;
}

sub _clear_mocking {
    undef $http;
    return 1;
}

1;
