package Cpanel::OSCAR::Signing;

# cpanel - Cpanel/OSCAR/Signing.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Digest::SHA ();
use HTTP::Tiny  ();

use Cpanel::Base64       ();
use Cpanel::Encoder::URI ();

sub get_base_string {
    my ( $method, $url, $params_hr, $salt ) = @_;

    $method =~ tr<a-z><A-Z>;

    #NOTE: The signing here depends on HTTP::Tiny’s advertised feature
    #of sorting the form parameters in the query string.

    my $query_string = HTTP::Tiny->www_form_urlencode($params_hr);

    #Strip out any port number that might be here.
    $url =~ s<\A ([^/]+//)? ([^/]+) : [0-9]+><$1$2>x;

    my $hash_data = join(
        '&',
        $method,

        #NOTE: This needs to be UPPER-CASE escaping.
        ( map { _uri_encode($_) } $url, $query_string ),
    );

    return Cpanel::Base64::pad( Digest::SHA::hmac_sha256_base64( $hash_data, $salt ) );
}

sub _uri_encode {
    my $txt = shift;

    my $encd = Cpanel::Encoder::URI::uri_encode_str($txt);
    $encd =~ s<(%..)>< $1 =~ tr(a-f)(A-F)r >ge;

    return $encd;
}

1;
