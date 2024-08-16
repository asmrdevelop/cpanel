package Cpanel::SSL::Legacy;

# cpanel - Cpanel/SSL/Legacy.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Legacy

=head1 SYNOPSIS

    my $key_pem = Cpanel::SSL::Legacy::generate_key_from_keysize_and_keytype(
        'bob', $keysize, $keytype,
    );

=head1 DESCRIPTION

This module implements certain legacy-accommodating logic for SSL APIs.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $pem = generate_key_from_keysize_and_keytype( $USERNAME, $KEYSIZE, $KEYTYPE )

Originally cPanel APIs for key generation exposed a C<keysize> argument to
control the size of the RSA key that was generated. When RSA was the only
key algorithm we supported this worked fine.

Once we added ECDSA, though, we needed a way for callers to create ECDSA keys,
which prompted the introduction of the C<keytype> argument and consequent
deprecation of C<keysize>.

This function implements handler logic for the two parameters. Its return is
the generated key in PEM format.

=cut

sub generate_key_from_keysize_and_keytype ( $username, $keysize, $keytype ) {
    my $key_pem;

    local ( $@, $! );

    if ($keytype) {
        if ($keysize) {
            die locale()->maketext( 'Provide “[_1]” or “[_2]”, not both.', 'keytype', 'keysize' );
        }

        require Cpanel::SSL::Create;

        if ( $keytype eq 'default' ) {

            # Use the reseller’s key-type preference.
            require Cpanel::SSL::DefaultKey::User;

            $keytype = Cpanel::SSL::DefaultKey::User::get($username);
        }

        $key_pem = Cpanel::SSL::Create::key($keytype);
    }
    else {
        require Cpanel::RSA;

        my $rsa_keysize = $keysize || $Cpanel::RSA::DEFAULT_KEY_SIZE;

        if ( $rsa_keysize !~ m/^\d+$/ ) {
            $rsa_keysize = $Cpanel::RSA::DEFAULT_KEY_SIZE;
        }
        elsif ( $rsa_keysize > 4096 ) {
            $rsa_keysize = 4096;
        }

        $key_pem = Cpanel::RSA::generate_private_key_string($rsa_keysize);
    }

    return $key_pem;
}

1;
