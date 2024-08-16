package Cpanel::Validate::OctalPermissions;

# cpanel - Cpanel/Validate/OctalPermissions.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

=encoding utf-8

=head1 MODULE

C<Cpanel::Validate::OctalPermissions>

=head1 DESCRIPTION

C<Cpanel::Validate::OctalPermissions> provides validation that checks if an integer is
a valid octal permission number (i.e., 0700)..

=head1 SYNOPSIS

    use Cpanel::Validate::OctalPermissions ();
    my $perm = '0700';
    if ( Cpanel::Validate::OctalPermissions::is_octal_permission($perm) {
        # OctalPermissions is a valid octal permission number.
    }
    $perm = 'invalid';
    # New permission is invalid, resulting in the method returning an exception.
    Cpanel::Validate::OctalPermissions::is_octal_permission_or_die($perm);

=cut

=head1 FUNCTIONS

=head2 is_octal_permission( PERM, NAME )

This method checks if a value is a valid octal permission number, such as
1777, 0644, etc.

The thrown exception is an instance of L<Cpanel::Exception::InvalidParameter>.

=head3 ARGUMENTS

=over

=item PERM - integer

Required. The integer to check.

=back

=head3 RETURNS

1 if the integer is a valid octal permission number.

0 if the integer is not an integer value.

=cut

sub is_octal_permission {
    my ($perm) = @_;

    # $perm should be defined.
    return 0 if !defined $perm;

    # If it is a non-numeric string, no need to check further.
    return 0 unless _verify_numerals_only($perm);

    # If the provided integer is unquoted, it will automatically be converted to an octal number.
    # As such, we will attempt to compare both the raw value, as well as a Unix-friendly format (via sprintf).
    if ( $perm !~ /^[0-7]{4}$/ && sprintf( '%04o', $perm ) !~ /0[0-7]{3}$/ ) {
        return 0;
    }

    return 1;
}

=head2 is_octal_permission_or_die( PERM, NAME )

This method is similar to C<is_octal_permission()>, but this method will die
if C<is_octal_permission()> returns 0.

The thrown exception is an instance of L<Cpanel::Exception::InvalidParameter>.

=head3 ARGUMENTS

=over

=item PERM - integer

Required. The integer to check.

=item NAME - string

Optional. If provided, exceptions will be generated with a parameter name included.

=back

=head3 RETURNS

1 if the integer is a valid octal permission number.

=head3 THROWS

If the integer is not an integer value.

=cut

sub is_octal_permission_or_die {
    my ( $perm, $name ) = @_;

    if ( !length $perm || $perm =~ m<\A\s+\z> ) {
        die Cpanel::Exception::create('Empty') if !$name;
        die Cpanel::Exception::create( 'Empty', [ name => $name ] );
    }

    _verify_numerals_only_or_die( $perm, $name );

    my $return = is_octal_permission($perm);
    if ( $return == 0 ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid octal permission.',                  [$perm] ) if !$name;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value “[_2]” is not a valid octal permission.', [ $name, $perm ] );
    }

    return;
}

sub _verify_numerals_only {
    my ($perm) = @_;

    my $bad_count = ( $perm =~ tr<0-9><>c );

    return ( $bad_count > 0 ) ? 0 : 1;
}

sub _verify_numerals_only_or_die {
    my ( $perm, $name ) = @_;

    if ( my $bad_count = ( $perm =~ tr<0-9><>c ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid octal permission integer because it contains [quant,_2,invalid character or integer,invalid characters or integers].', [ $perm, $bad_count ] ) if !$name;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value “[_2]” is not a valid octal permission integer because it contains [quant,_3,invalid character or integer,invalid characters or integers].', [ $name, $perm, $bad_count ] );
    }

    return;
}

1;
