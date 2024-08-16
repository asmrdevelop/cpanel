package Cpanel::SSL::Sign;

# cpanel - Cpanel/SSL/Sign.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception        ();
use Cpanel::TempFile         ();
use Cpanel::FileUtils::Write ();
use Cpanel::LoadModule       ();

#########################################################################
#
# Method:
#   smime_sign_with_certificate
#
# Description:
#   Sign data using the certificate and key that are installed
#   for the specified service.
#
# Parameters:
#
#   payload           - The data to sign
#   (required)
#
#   certificate       - An ssl certificate in PEM format.
#   (required)
#
#   key               - An ssl key in PEM format for the
#   (required)          certificate
#
#   cabundle          - An ssl chain in PEM format for the
#   (required)          certificate.
#
# Returns:
#   The signed payload
#

sub smime_sign_with_certificate {
    my (%OPTS) = @_;

    foreach my $required (qw(payload certificate key)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !length $OPTS{$required};
    }

    my $payload     = $OPTS{'payload'};
    my $certificate = $OPTS{'certificate'};
    my $key         = $OPTS{'key'};
    my $cabundle    = $OPTS{'cabundle'};

    my $temp_obj      = Cpanel::TempFile->new();
    my $temp_key_file = $temp_obj->file();
    my $temp_crt_file = $temp_obj->file();
    my $temp_cab_file;

    Cpanel::FileUtils::Write::overwrite( $temp_key_file, $key, 0600 );
    Cpanel::FileUtils::Write::overwrite( $temp_crt_file, $certificate );
    if ($cabundle) {
        $temp_cab_file = $temp_obj->file();
        Cpanel::FileUtils::Write::overwrite( $temp_cab_file, $cabundle );
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::OpenSSL');
    my $openssl     = Cpanel::OpenSSL->new();
    my $openssl_ret = $openssl->run(
        stdin  => $payload,
        'args' => [
            'smime',
            '-sign',
            '-outform' => 'der',
            '-nodetach',
            '-signer' => $temp_crt_file,
            '-inkey'  => $temp_key_file,
            ( $temp_cab_file ? ( '-certfile' => $temp_cab_file ) : () ),
        ],
    );

    if ( $openssl_ret->{'stderr'} ) {
        die Cpanel::Exception->create( "Signing mobileconfig with openssl smime failed with an error: [_1]", [ $openssl_ret->{'stderr'} ] );
    }

    return $openssl_ret->{'stdout'};

}

1;
