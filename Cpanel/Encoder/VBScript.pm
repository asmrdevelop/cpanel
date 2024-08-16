package Cpanel::Encoder::VBScript;

# cpanel - Cpanel/Encoder/VBScript.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our $VERSION = '1.0';

sub encode_vbscript_str {
    my ($string) = @_;

    $string =~ s/"/""/g;
    return $string;
}

1;
