package Cpanel::Crypt::ECDSA::Validate;

# cpanel - Cpanel/Crypt/ECDSA/Validate.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Crypt::ECDSA::Validate

=head1 SYNOPSIS

    Cpanel::Crypt::ECDSA::Validate::validate_curve_name_and_point(
        $curve_name, $point_hex,
    );

=head1 DESCRIPTION

This module culls together validation logic that gets used in multiple
interfaces.

=cut

#----------------------------------------------------------------------

use Cpanel::Crypt::ECDSA::Data ();
use Cpanel::Exception          ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 validate_curve_name_and_point( $CURVE_NAME, $POINT_HEX )

Validates that the $CURVE_NAME and $POINT_HEX are in the expected
form. Throws a L<Cpanel::Exception::InvalidParameter> instance otherwise.

Returns nothing.

=cut

sub validate_curve_name_and_point ( $curve_name, $point_hex ) {
    if ( !Cpanel::Crypt::ECDSA::Data::curve_name_is_valid($curve_name) ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "Invalid curve name ($curve_name)!" );
    }

    if ( $point_hex =~ tr<0-9a-f><>c ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "Invalid point: [$point_hex]" );
    }

    if ( 0 != rindex( $point_hex, '02', 0 ) && 0 != rindex( $point_hex, '03', 0 ) ) {
        die Cpanel::Exception::create_raw( 'InvalidParameter', "Point ($point_hex) must be compressed!" );
    }

    return;
}

1;
