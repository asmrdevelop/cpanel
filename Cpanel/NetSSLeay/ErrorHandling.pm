package Cpanel::NetSSLeay::ErrorHandling;

# cpanel - Cpanel/NetSSLeay/ErrorHandling.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::NetSSLeay::ErrorHandling

=head1 DESCRIPTION

This module contains logic to parse OpenSSL errors from L<Net::SSLeay>.

=cut

#----------------------------------------------------------------------

use Net::SSLeay ();

#----------------------------------------------------------------------

use Net::SSLeay ();

=head1 FUNCTIONS

=head2 @codes = get_error_codes()

Returns all error codes from OpenSSL’s queue, leaving that queue empty.

(Returns the number of such codes in scalar context.)

=cut

sub get_error_codes() {
    my @err_codes;

    while ( my $code = Net::SSLeay::ERR_get_error() ) {
        push @err_codes, $code;
    }

    return @err_codes;
}

=head2 ERR_GET_LIB($code)

Each OpenSSL error code is a packed representation of three numbers:
library (8 bits), function (12 bits), reason (12 bits).

(cf. OpenSSL’s F<include/openssl/err.h>)

This function returns the library component of such an error code.

=cut

sub ERR_GET_LIB ($code) {
    return ( ( $code >> 24 ) & 0xff );
}

=head2 ERR_GET_FUNC($code)

Like C<ERR_GET_LIB()> but returns the function component.

=cut

sub ERR_GET_FUNC ($code) {
    return ( ( $code >> 12 ) & 0xfff );
}

=head2 ERR_GET_REASON($code)

Like C<ERR_GET_LIB()> but returns the reason component.

=cut

sub ERR_GET_REASON ($code) {
    return ( $code & 0xfff );
}

1;
