package Cpanel::Validate::FilesystemNodeName;

# cpanel - Cpanel/Validate/FilesystemNodeName.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception        ();
use Cpanel::Linux::Constants ();

#This throws no exception but also returns no error message.
sub is_valid {
    my ($node) = @_;

    local $@;
    eval { validate_or_die($node); };

    return $@ ? 0 : 1;
}

#This will throw an exception.
sub validate_or_die {
    my ($name) = @_;

    if ( !length $name ) {
        die Cpanel::Exception::create('Empty');
    }
    elsif ( $name eq '.' || $name eq '..' ) {
        die Cpanel::Exception::create( 'Reserved', [ value => $name ] );
    }
    elsif ( length $name > Cpanel::Linux::Constants::NAME_MAX() ) {
        die Cpanel::Exception::create( 'TooManyBytes', [ value => $name, maxlength => Cpanel::Linux::Constants::NAME_MAX() ] );
    }
    elsif ( index( $name, '/' ) != -1 ) {
        die Cpanel::Exception::create( 'InvalidCharacters', [ value => $name, invalid_characters => ['/'] ] );
    }
    elsif ( index( $name, "\0" ) != -1 ) {
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value may not contain a [asis,NUL] byte.', [ value => $name, invalid_characters => ["\0"] ] );
    }

    return 1;
}

1;
