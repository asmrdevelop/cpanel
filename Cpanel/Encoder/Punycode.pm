package Cpanel::Encoder::Punycode;

# cpanel - Cpanel/Encoder/Punycode.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0';

sub punycode_encode_str {
    my ($string) = @_;

    # If the string only contains ASCII characters we do not
    # need to encode it since Net::IDN::Encode::domain_to_ascii is
    # effectively going to do nothing in this case.  In this case
    # we avoid the load of Net::IDN::Encode and the subsequent encoding
    # and just return the string.
    #
    # It should be noted that this function does nothing to validate
    # that the string being passed in is valid.
    return $string if $string !~ tr<\x00-\x7f><>c;

    # http://charset.org/ can turn these '@' back into the original Unicode
    my $at_at = index( $string, '@' );

    require Cpanel::UTF8::Strict;
    require Net::IDN::Encode;
    if ( $at_at > -1 ) {

        # TODO: ? multiple @ signs ...
        # my ($dom,$nam) = split(/\@/,reverse($string),2);
        #        $dom = reverse($dom);
        #        $nam = reverse($nam);
        #
        my $local_part = substr( $string, 0, $at_at );
        my $domain     = substr( $string, 1 + $at_at );
        Cpanel::UTF8::Strict::decode($local_part);
        Cpanel::UTF8::Strict::decode($domain);

        return Net::IDN::Encode::domain_to_ascii($local_part) . '@' . Net::IDN::Encode::domain_to_ascii($domain);
    }

    # this will act funny if there are @ symbols:
    Cpanel::UTF8::Strict::decode($string);
    return Net::IDN::Encode::domain_to_ascii($string);
}

sub punycode_decode_str {
    my ($string) = @_;

    return $string if index( $string, 'xn--' ) == -1;

    # http://charset.org/ turns email-like '@' strings into this
    require Net::IDN::Encode;
    my $at_at = index( $string, '@' );
    if ( -1 != $at_at ) {

        # TODO: ? multiple @ signs ...
        # my ($dom,$nam) = split(/\@/,reverse($string),2);
        #        $dom = reverse($dom);
        #        $nam = reverse($nam);
        my $local_part = Net::IDN::Encode::domain_to_unicode( substr( $string, 0, $at_at ) );
        my $domain     = Net::IDN::Encode::domain_to_unicode( substr( $string, 1 + $at_at ) );
        utf8::encode($local_part);
        utf8::encode($domain);
        return $local_part . '@' . $domain;
    }

    # this will act funny if there are @ symbols:
    my $str = Net::IDN::Encode::domain_to_unicode($string);
    utf8::encode($str);
    return $str;

}

1;
