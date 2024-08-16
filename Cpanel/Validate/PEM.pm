package Cpanel::Validate::PEM;

# cpanel - Cpanel/Validate/PEM.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Validate::PEM

=head1 DESCRIPTION

This module validates a PEM-encoded blob, e.g., an SSL key or certificate.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception        ();
use Cpanel::Validate::Base64 ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 validate_or_die( $SPECIMEN )

Throws an appropriate L<Cpanel::Exception> instance of $SPECIMEN is not
valid PEM.

=cut

sub validate_or_die ($specimen) {
    $specimen =~ s<\A \s* ----- BEGIN [ ] ([A-Z ]+?) -----\x0d?\x0a><>x or do {
        die Cpanel::Exception::create( 'InvalidParameter', 'This value lacks a [asis,PEM] header.' );
    };

    my $name1 = $1;

    $specimen =~ s<\x0d?\x0a ----- END [ ] ([A-Z ]+?) -----\x0d?\x0a?\z><>x or do {
        die Cpanel::Exception::create( 'InvalidParameter', 'This value lacks a [asis,PEM] footer.' );
    };

    my $name2 = $1;

    if ( $name1 ne $name2 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'This value’s [asis,PEM] header and footer (“[_1]” and “[_2]”) do not match.', [ $name1, $name2 ] );
    }

    return Cpanel::Validate::Base64::validate_or_die($specimen);
}

1;
