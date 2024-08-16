
# cpanel - Cpanel/StringFunc/Fmt.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::StringFunc::Fmt;

use strict;

use Cpanel::UTF8 ();

our $ALIGN_LEFT  = 0;
our $ALIGN_RIGHT = 1;

#This function line-wraps a string $text to a maximum of $max characters.
#It assumes UTF-8.
sub bare_wrap {
    my ( $text, $max )  = @_;
    my ( $ret,  $line ) = ( '', '' );
    $text =~ s{$/$/}{$/\f$/}g;
    for ( split m{[$/\t ]+}, $text ) {
        if ( ( $_ eq "\f" ) || ( $line && Cpanel::UTF8::char_count($line) + Cpanel::UTF8::char_count($_) > $max ) ) {
            $ret .= ( $ret ? $/ : '' ) . $line;
            if ( $_ eq "\f" ) {
                $ret .= $/;
                $line = '';
            }
            else {
                $line = $_;
            }
        }
        else {
            $line .= ( $line ? ' ' : '' ) . $_;
        }
    }

    if ( length $line ) {
        $ret .= ( length $ret ? $/ : q{} ) . $line;
    }

    return $ret;
}

#Adds a trailing $/
sub wrap {
    my ( $text, $max ) = @_;

    return bare_wrap( $text, $max ) . $/;
}

#This will return a string that is exactly $length characters long.
#Note that that is CHARACTERS, not bytes, since the obvious use case
#here is in displays.
#
#$align accepts one of $ALIGN_LEFT (default) or $ALIGN_RIGHT, above.
#
sub fixed_length {
    my ( $text, $length, $align ) = @_;

    my $text_is_ascii = $text !~ tr/\x00-\x7E//c ? 1 : 0;
    my $fixed_txt;
    if ( defined $length ) {
        if ($text_is_ascii) {
            $fixed_txt = substr( $text, 0, $length );
        }
        else {
            my $chars_ar = Cpanel::UTF8::get_unicode_as_character_list($text);
            splice @$chars_ar, $length if $length < @$chars_ar;
            $fixed_txt = join( q<>, @$chars_ar );
        }
    }
    else {
        $fixed_txt = $text;
    }

    my $char_count = $text_is_ascii ? length $fixed_txt : Cpanel::UTF8::char_count($fixed_txt);

    if ( $char_count < $length ) {
        if ( $align && $align == $ALIGN_RIGHT ) {
            my $padding = ' ' x ( $length - $char_count );
            substr( $fixed_txt, 0, 0, $padding );
        }
        else {
            return pack( "A$length", $fixed_txt );
        }
    }

    return $fixed_txt;
}

1;
