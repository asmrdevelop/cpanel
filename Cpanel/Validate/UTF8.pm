package Cpanel::Validate::UTF8;

# cpanel - Cpanel/Validate/UTF8.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

#NOTE: use utf8 is explictly not required per the utf8 man page

#We've had builds fail before when we included this code point
#in code via \x{..}, so check for it as a byte string explicitly.
use constant ucs_7fffffff => "\xfd\xbf\xbf\xbf\xbf\xbf";

sub or_die {
    my ($copy) = @_;

    #See above about code point U+7fffffff.
    if ( -1 != index $copy, ucs_7fffffff() ) {
        _die_invalid_code_point( $copy, 0x7fffffff );
    }

    #This detects: http://www.perlmonks.org/?node_id=644786
    utf8::decode($copy) or do {
        die Cpanel::Exception::create( 'InvalidUTF8', [ value => $copy ] );
    };

    #Prevents the following warning:
    #
    #   Code point 0x861861 is not Unicode, no properties match it;
    #   all inverse properties do
    #
    no warnings 'utf8';

    #Per RFC 3629, anything above U+1fffff is not valid Unicode.
    if ( length $copy ) {
        if ( $copy =~ m/([\x{200000}-\x{7ffffffe}])/ ) {
            my $bad_code_point = ord $1;
            utf8::encode($copy);
            _die_invalid_code_point( $copy, $bad_code_point );
        }
    }

    return;
}

sub _die_invalid_code_point {
    my ( $byte_string, $bad_code_point ) = @_;

    die Cpanel::Exception::create( 'InvalidUTF8::CodePoint', [ value => $byte_string, code_point => $bad_code_point ] );
}

1;
