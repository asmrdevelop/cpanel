package Cpanel::Validate::PwFileEntry;

# cpanel - Cpanel/Validate/PwFileEntry.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Exception                    ();
use Cpanel::Validate::LineTerminatorFree ();

my $MAX_LENGTH = 4096;

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

    if ( $name =~ tr{:}{} ) {
        die Cpanel::Exception::create( 'InvalidCharacters', [ value => $name, invalid_characters => [':'] ] );
    }
    elsif ( length $name > $MAX_LENGTH ) {
        die Cpanel::Exception::create( 'TooManyBytes', [ value => $name, maxlength => $MAX_LENGTH ] );
    }
    Cpanel::Validate::LineTerminatorFree::validate_or_die($name);

    return 1;
}

1;
