package Cpanel::DataURI;

# cpanel - Cpanel/DataURI.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Autodie ();
use MIME::Base64    ();

use constant READ_CHUNK => 3420;    #60 * 57, per MIME::Base64 docs

=encoding utf-8

=head1 NAME

Cpanel::DataURI - Easy data URI creation

=head1 SYNOPSIS

    $uri = Cpanel::DataURI::create( 'image/png', $png_buffer );

    $uri = Cpanel::DataURI::create_from_fh( 'image/png', $png_fh );

=head1 FUNCTIONS

=head2 create( MIME_TYPE, BUFFER ) create_from_fh( MIME_TYPE, FILEHANDLE )

This returns a data URI from the given inputs.

=cut

sub create {
    my ($type) = @_;    #$_[1] = data

    die "Data cannot be empty!" if !length $_[1];

    return _create( $type, \MIME::Base64::encode_base64( $_[1] ) );
}

sub create_from_fh {
    my ( $type, $fh ) = @_;

    my ( $uri, $buf );
    while ( Cpanel::Autodie::read( $fh, $buf, READ_CHUNK ) ) {
        $uri .= MIME::Base64::encode_base64($buf);
    }

    return _create( $type, \$uri );
}

sub _create {
    my ( $type, $b64_sr ) = @_;

    die "Need a type!" if !length $type;

    #Base64
    $$b64_sr =~ tr<\r\n><>d;

    return "data:$_[0];base64,$$b64_sr";
}

1;
