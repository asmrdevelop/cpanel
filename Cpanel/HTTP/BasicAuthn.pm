package Cpanel::HTTP::BasicAuthn;

# cpanel - Cpanel/HTTP/BasicAuthn.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::HTTP::BasicAuthn

=head1 SYNOPSIS

    my ($hdr, $value) = Cpanel::HTTP::BasicAuthn::encode( 'bob', '$3kr3+' );

=head1 DESCRIPTION

This module implements logic for
HTTP Basic Authentication as defined in
L<RFC 7617|https://tools.ietf.org/html/rfc7617>.

=cut

#----------------------------------------------------------------------

use MIME::Base64 ();

use Cpanel::Context ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 ($header, $value) = encode( $USERNAME, $PASSWORD )

Returns a header and a value to include in the HTTP request.

=cut

sub encode ( $un, $pw ) {
    Cpanel::Context::must_be_list();

    if ( -1 != index( $un, ':' ) ) {
        die "username ($un) MUST NOT contain “:”!";
    }

    my $val = MIME::Base64::encode("$un:$pw");
    chop $val;

    return ( Authorization => "Basic $val" );
}

1;
