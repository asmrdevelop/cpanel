package Cpanel::UTF8;

# cpanel - Cpanel/UTF8.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# TODO: refactor so we do not need the defunct bytes pragma, ick
use bytes;    #Required!

# See String::UnicodeUTF8 for ideas and principles that would be good to employ here for simplicity, consistency, and clarity.
#
# The naming (i.e. based on the 2 item glossary as well as the ideas behind them) and behavior (e.g. operate
#     consistently given either utf8 bytes or a unicode string) are good to imitate for a number of reasons (that
#     should become clear as you go through the documentation for String::UnicodeUTF8).

sub char_count {    # Get the number of characters, conceptually, of the given string regardless of the argument’s type.
                    # $_[0]: str
    return scalar @{ get_unicode_as_code_point_list( $_[0] ) };    ##no critic (RequireArgUnpacking)
}

sub get_unicode_as_character_list {    # Get a “Unicode String” version as a list of characters of the given string regardless of the argument’s type.
                                       # $_[0]: str
    return [ map { pack 'U', $_ } @{ get_unicode_as_code_point_list( $_[0] ) } ];    ##no critic (RequireArgUnpacking)
}

sub get_unicode_as_code_point_list {    # Get a “Unicode String” version as a list of code poiints of the given string regardless of the argument’s type.
                                        # $_[0]: str
    return [ unpack 'C0U*', $_[0] ];    ##no critic (RequireArgUnpacking)
}

# AKA String::UnicodeUTF8::get_unicode for perl 5.6
sub get_unicode_string_from_bytes_string {    ## no critic (RequireArgUnpacking)
    return pack 'U0C*', unpack 'C*', join( '', @_ );
}

sub get_bytes_string_from_unicode_string {    ## no critic (RequireArgUnpacking)
    no bytes;                                 # usage of bytes was causing this join to return a bytes string.
    return pack 'C0U*', unpack 'U*', join( '', @_ );
}

1;
