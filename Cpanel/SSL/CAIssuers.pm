package Cpanel::SSL::CAIssuers;

# cpanel - Cpanel/SSL/CAIssuers.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::CAIssuers - fetch a CA bundle based on the C<caIssuers> URL

=head1 SYNOPSIS

    my $cert_obj = Cpanel::SSL::Objects::Certificate->new( cert => $pem );

    my $url = $cert_obj->caIssuers_url();

    my $cab_pem = Cpanel::SSL::CAIssuers::get_cabundle_pem($url);

=head1 DISCUSSION

CA guidelines stipulate that the C<authorityInfoAccess> extension
“SHOULD” be part of all newly-issued certificates. This extension, per
the guidelines, “SHOULD” contain a C<caIssuers> URL that gives the
next certificate(s) up the authority chain. That next certificate, in turn,
should also contain a C<caIssuers> URL; ultimately, we should be able to
recurse through and fetch the entire CA bundle.

You probably don’t want to call into this directly since if we don’t
cache the results of this we risk hammering CAs with millions of requests
for these certificates; instead, look at L<Cpanel::SSL::CABundleCache>.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Crypt::Format ();
use URI::Split    ();

use Cpanel::Exception                 ();
use Cpanel::HTTP::Client              ();
use Cpanel::IP::LocalCheck            ();
use Cpanel::LoadModule                ();
use Cpanel::Security::Authz           ();
use Cpanel::SocketIP                  ();
use Cpanel::SSL::Objects::Certificate ();

=head2 get_cabundle_pem( URL )

Returns the CA bundle as a newline-joined sequence of certificates in PEM
format, with the “leaf” node first.

=cut

#Returns undef if the cert has no link to the next certificate
#up the chain.
sub get_cabundle_pem {
    my ($url) = @_;

    #There *shouldn’t* be a problem with doing this as root,
    #but to be safe we want to minimize our use of OpenSSL as root.
    Cpanel::Security::Authz::verify_fully_reduced();

    my $orig_url = $url;

    my @pem_chain;

    my $http = Cpanel::HTTP::Client->new()->die_on_http_error();

  URL:
    while ($url) {
        my $ipv4 = _check_url($url);

        #Might as well pass the “peer”; no reason to look it up twice.
        my $get     = $http->get( $url, { peer => $ipv4 } );
        my $content = $get->content();

        my @pems;

        my $type = $get->header('content-type');

        #PKCS7. Let’s Encrypt does this.
        if ( $type && $type =~ m<pkcs7>i ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::SSL::P7C');
            @pems = Cpanel::SSL::P7C::get_certificates($content);
        }

        #GoDaddy gives PEM.
        #http://certificates.godaddy.com/repository/gdig2.crt
        elsif ( 0 == index( $content, '-----' ) ) {
            $content =~ s<[\r\n]+\z><>;
            @pems = ($content);
        }

        #Most URLs give DER.
        else {
            @pems = ( Crypt::Format::der2pem( $content, 'CERTIFICATE' ) );
        }

        #If a cert references itself, there’s probably nothing wrong,
        #but we need not to get caught in an infinite loop from it.
        last if @pem_chain && Crypt::Format::pem2der( $pems[0] ) eq Crypt::Format::pem2der( $pem_chain[-1] );

        my $cert;

        #Now check for multi-certificate, self-referential loops.
        #(We already checked the last cert in the chain.)
        #This almost certainly indicates foul play if we have one.
        for my $pem (@pems) {
            if ( grep { $_ eq $pem } @pem_chain[ 0 .. ( $#pem_chain - 1 ) ] ) {
                die Cpanel::Exception->create_raw("Self-referential [asis,caIssuers] loop detected! ($orig_url)");
            }

            $cert = Cpanel::SSL::Objects::Certificate->new( cert => $pem );

            #There’s no point in including a root certificate.
            last URL if $cert->is_self_signed();

            push @pem_chain, $pem;
        }

        $url = $cert->caIssuers_url();
    }

    my $cab_pem = join "\n", @pem_chain;

    # We used to verify the cert chain at this point,
    # but there’s no real reason to do so since we might have fetched
    # the chain for the specific purpose of doing verification.

    return $cab_pem;
}

sub _check_url {
    my ($url) = @_;

    my ( $schema, $authority ) = URI::Split::uri_split($url);

    if ( $schema ne 'http' && $schema ne 'https' ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not an [asis,HTTP(S)] [asis,URL].', [$url] );
    }

    my $ipv4 = _domain_to_ip($authority);
    if ( !$ipv4 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The system did not determine an [asis,IPv4] address for the domain “[_1]” (from the [asis,URL] “[_2]”).', [ $authority, $url ] );
    }

    if ( _ip_is_on_local_server($ipv4) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The domain “[_1]” (from the [asis,URL] “[_2]”) resolves to an [asis,IPv4] address ([_3]) that is on this server.', [ $authority, $url, $ipv4 ] );
    }

    return $ipv4;
}

#overridden in tests
*_domain_to_ip          = \&Cpanel::SocketIP::_resolveIpAddress;
*_ip_is_on_local_server = \&Cpanel::IP::LocalCheck::ip_is_on_local_server;

1;
