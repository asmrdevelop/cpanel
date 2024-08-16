package Cpanel::Crypt::Constants;

# cpanel - Cpanel/Crypt/Constants.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Crypt::Constants

=head1 DESCRIPTION

Constants for cryptography.

=cut

#----------------------------------------------------------------------

=head1 CONSTANTS

=head2 ALGORITHM_RSA

The string used for RSA (e.g., after parsing a certificate).

=cut

=head2 ALGORITHM_ECDSA

Like C<ALGORITHM_RSA> but for ECDSA.

=cut

use constant {
    ALGORITHM_RSA   => 'rsaEncryption',
    ALGORITHM_ECDSA => 'id-ecPublicKey',
};

1;
