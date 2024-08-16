package Cpanel::Validate::PackageName;

# cpanel - Cpanel/Validate/PackageName.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception ();

use Cpanel::Validate::FilesystemNodeName ();

#This throws no exception but also returns no error message.
sub is_valid {
    my ($name) = @_;

    local $@;
    return eval { validate_or_die($name) } ? 1 : 0;
}

#This will throw an exception.
sub validate_or_die {
    my ($name) = @_;

    Cpanel::Validate::FilesystemNodeName::validate_or_die($name);

    if ( $name =~ m{\A\s+\z} ) {
        die Cpanel::Exception::create('Empty');
    }

    if ( $name eq 'undefined' || $name eq 'extensions' ) {
        die Cpanel::Exception::create( 'Reserved', '“[_1]” is a reserved package name.', [$name] );
    }

    my $original_name = $name;

    $name =~ tr<a-zA-Z0-9 ._-><>d;    # Remove allowed characters

    if (
        $name =~ tr<\x00-\x7f><>      # If we have characters leftover that are not allowed
        || !utf8::decode($name)       # or invalid utf-8

    ) {
        die Cpanel::Exception::create( 'InvalidCharacters', '“[_1]” is invalid. A package name may only contain multi-byte UTF-8 characters, spaces, and the following: [join, ,_2]', [ $original_name, [ 'a-z', 'A-Z', '0-9', '.', '_', '-' ] ] );
    }

    return 1;
}

1;
