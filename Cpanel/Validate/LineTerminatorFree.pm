package Cpanel::Validate::LineTerminatorFree;

# cpanel - Cpanel/Validate/LineTerminatorFree.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#----------------------------------------------------------------------
#NOTE: This module’s code is to be moved into Whitespace.pm in 11.50.
#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Encoder::utf8 ();
use Cpanel::Exception     ();

#This throws no exception but also returns no error message.
sub is_valid {
    my ($node) = @_;

    my $err;
    try {
        validate_or_die($node);
    }
    catch {
        $err = $_;
    };

    return $err ? 0 : 1;
}

#This will throw an exception.
sub validate_or_die {
    my ($name) = @_;

    # From wikipedia
    #
    #  LF:    Line Feed, U+000A
    #  VT:    Vertical Tab, U+000B
    #  FF:    Form Feed, U+000C
    #  CR:    Carriage Return, U+000D
    #  CR+LF: CR (U+000D) followed by LF (U+000A)
    #  NEL:   Next Line, U+0085
    #  LS:    Line Separator, U+2028
    #  PS:    Paragraph Separator, U+2029

    if ( $name =~ tr/\x{000A}// ) {    # LF: (CR+LF)
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a line feed.', [ value => $name, invalid_characters => ["\x{000A}"] ] );
    }
    elsif ( $name =~ tr/\x{000B}// ) {    # VT:
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a vertical tab.', [ value => $name, invalid_characters => ["\x{000B}"] ] );
    }
    elsif ( $name =~ tr/\x{000C}// ) {    # FF:
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a form feed.', [ value => $name, invalid_characters => ["\x{000C}"] ] );
    }
    elsif ( $name =~ tr/\x{000D}// ) {    # CR: (CR+LF)
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a carriage return.', [ value => $name, invalid_characters => ["\x{000D}"] ] );
    }
    elsif ( $name =~ tr/\x{0085}// ) {    # NEL:
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a Unicode [asis,NEL] character.', [ value => $name, invalid_characters => ["\x{0085}"] ] );
    }

    Cpanel::Encoder::utf8::encode($name);

    if ( -1 != index( $name, "\xe2\x80\xa8" ) ) {    # LS:
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a Unicode [asis,LS] character..', [ value => $name, invalid_characters => ["\x{2028}"] ] );
    }
    elsif ( -1 != index( $name, "\xe2\x80\xa9" ) ) {    # PS:
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a Unicode [asis,PS] character.', [ value => $name, invalid_characters => ["\x{2029}"] ] );
    }
    elsif ( $name =~ tr{\0}{} ) {
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a [asis,NUL] byte.', [ value => $name, invalid_characters => ["\0"] ] );
    }

    return 1;
}

1;
