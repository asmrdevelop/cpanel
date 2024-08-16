package Cpanel::Encoder::HTTP;

# cpanel - Cpanel/Encoder/HTTP.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::UTF8 ();

# see http://stackoverflow.com/questions/93551/how-to-encode-the-filename-parameter-of-content-disposition-header-in-http
my %ANDROID_SAFE_CHARACTERS = map { $_ => 1 } (

    #7-bit alpha
    'a' .. 'z',
    'A' .. 'Z',

    #7-bit numerals
    0 .. 9,

    #7-bit punctuation
    ',', qw/ - . _ + @ $ ! ~ ' = [ ] { } ( ) /,

    #multi-byte
    qw/ £ € ½ § /,
);

my $REPLACEMENT = '_';

# Note: downloads break if we do not convert this back
# to a bytes string
sub android_safe_filename {
    my ($filename) = @_;

    return Cpanel::UTF8::get_bytes_string_from_unicode_string( join q<>, map { $ANDROID_SAFE_CHARACTERS{$_} ? $_ : $REPLACEMENT } @{ Cpanel::UTF8::get_unicode_as_character_list($filename) } );
}

1;
