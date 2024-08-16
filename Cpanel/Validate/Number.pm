package Cpanel::Validate::Number;

# cpanel - Cpanel/Validate/Number.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Validate::Number - validation for numbers

=head1 SYNOPSIS

    use Cpanel::Validate::Number;

    Cpanel::Validate::Number::rational_number('4');     #good
    Cpanel::Validate::Number::rational_number('4.1');   #good
    Cpanel::Validate::Number::rational_number('-4.0');  #good

    Cpanel::Validate::Number::rational_number('-4.');   #die()

=head1 DESCRIPTION

validation for numbers

=cut

use Cpanel::Exception ();

=head2 rational_number

Returns if the SPECIMEN is a valid rational number (i.e., can be positive
or negative and can include fractions).

=over 2

=item Input

=over 3

=item C<SCALAR>

    SPECIMEN - number to check and determine if it's rational

=back

=item Output

=over 3

=item C<NONE>

    does not return a value



=back

=item Throws

=over 3

=item L<Cpanel::Exception::InvalidParameter>

    Throws if not SPECIMEN is not a valid rational number

=back

=back

=cut

sub rational_number {
    $_[0] =~ /^[-+]?[0-9]*\.?[0-9]+$/ or do {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid rational number.', [ $_[0] ] );
    };

    return;
}

1;
