package Cpanel::Validate::Base64;

# cpanel - Cpanel/Validate/Base64.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This will ONLY accept unpadded or correctly padded Base64. So:
#
#   aa          - valid
#   aa=         - invalid
#   aa==        - valid
#   aa===       - invalid
#   abcd====    - invalid
#
# This allows whitespace because some encoders chunk Base64 in lines.
#----------------------------------------------------------------------

use strict;

use Cpanel::Exception ();

my @invalid_equals_regexps = (
    '=[^=]',
    '\\A=',
    '====',
    '\\A(.{4})*.{0,2}=\\z',    #i.e., unnecessary padding
);

sub validate_or_die {    ##no critic qw(RequireArgUnpacking)
                         # $_[0]: b64

    _verify_not_empty( $_[0] );

    if ( $_[0] =~ m<[^\s0-9a-zA-Z+/=]> ) {
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value contains invalid [asis,Base64] characters.' );
    }

    my $specimen = ( $_[0] =~ s<\s+><>gr );

    if ( my @match = grep { $specimen =~ m<$_>s } @invalid_equals_regexps ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not valid in [asis,Base64] except to pad the end of the string.', ['='] );
    }

    return 1;
}

sub validate_url_or_die {    ##no critic qw(RequireArgUnpacking)
                             # $_[0]: b64
    _verify_not_empty( $_[0] );

    if ( $_[0] =~ m<[^0-9a-zA-Z_-]> ) {
        die Cpanel::Exception::create( 'InvalidCharacters', 'This value contains invalid [asis,Base64-URL] characters.' );
    }

    return;
}

sub _verify_not_empty {    ##no critic qw(RequireArgUnpacking)
    die Cpanel::Exception::create('Empty') if !length $_[0];
    die Cpanel::Exception::create('Empty') if $_[0] =~ m<\A\s*\z>;

    return;
}

1;
