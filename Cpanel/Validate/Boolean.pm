package Cpanel::Validate::Boolean;

# cpanel - Cpanel/Validate/Boolean.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

sub is_valid {
    my ($val) = @_;
    return 0 if !defined $val;
    return ( $val =~ /\A[10]\z/ ? 1 : 0 );
}

sub validate_or_die {
    if ( !length $_[0] || $_[0] =~ m<\A\s+\z> ) {
        die Cpanel::Exception::create('Empty') if !$_[1];
        die Cpanel::Exception::create( 'Empty', [ name => $_[1] ] );
    }

    if ( !is_valid( $_[0] ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,Boolean]. It must be one of: [list_or,_2].', [ $_[0], [ '0', '1' ] ] ) if !$_[1];
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” argument contains the value “[_2]”, which is an invalid [asis,Boolean] value. Boolean values are either [list_or,_3].', [ $_[1], $_[0], [ '0', '1' ] ] );
    }

    return 1;
}

1;
