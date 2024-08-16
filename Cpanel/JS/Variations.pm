package Cpanel::JS::Variations;

# cpanel - Cpanel/JS/Variations.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

sub lex_filename_for {
    my ( $filename, $locale ) = @_;
    return if !$filename || !$locale;
    return get_base_file( $filename, "-${locale}.js" );
}

sub get_base_file {
    my ( $filename, $replace_extension ) = @_;
    return if !$filename;
    $replace_extension //= '.js';
    $filename =~ s{/js2-min/}{/js2/};
    $filename =~ s{(?:[\.\-]min|_optimized)?\.js$}{$replace_extension};
    return $filename;
}

1;
