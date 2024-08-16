package Cpanel::Encoder::JSON;

# cpanel - Cpanel/Encoder/JSON.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my %JSON_ENCODE_MAP = ( "\n" => '\n', "\r" => '\r', "\t" => '\t', "\f" => '\f', "\b" => '\b', "\"" => '\"', "\\" => '\\\\', "\'" => '\\\'', '/' => '\\/' );

sub json_encode_str {
    my ($str) = @_;

    return 'null' if !defined $str;
    if ( $str =~ tr{A-Za-z0-9._-}{}c ) {
        $str =~ s{([\x22\x5c\n\r\t\f\b/])}{$JSON_ENCODE_MAP{$1}}g if $str =~ tr{\x22\x5c\n\r\t\f\b/}{};
        $str =~ s/([\x00-\x07\x0b\x0e-\x1f<\x7f])/'\\u00' . unpack('H2', $1)/eg;
    }
    return '"' . $str . '"';
}

1;
