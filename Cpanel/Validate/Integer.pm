package Cpanel::Validate::Integer;

# cpanel - Cpanel/Validate/Integer.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OSSys::Bits ();

=encoding utf-8

=head1 MODULE

C<Cpanel::Validate::Integer>

=head1 DESCRIPTION

C<Cpanel::Validate::Integer> provides validation that checks if an integer is
a nonnegative integer that does not exceed a maximum integer.

=head1 SYNOPSIS

    use Cpanel::Validate::Integer ();
    my $int = 15;
    my $max_int = 200;
    if ( Cpanel::Validate::Integer::unsigned_and_less_than( $int, $max_int, 'parameter' ) {
        # Integer is a nonnegative value that is less than $max_int
    }

=cut

use Cpanel::Exception ();

=head1 FUNCTION

=head2 unsigned_and_less_than( VAL, MAX, NAME )

As you might expect … it throws if VAL is invalid; otherwise
it returns (empty). This is smart enough to compare numeric strings when
the number itself exceeds what Perl can store in a number (Iv).

The thrown exception is an instance of L<Cpanel::Exception::InvalidParameter>
with a string that describes what’s wrong with the input.

This rejects leading C<0> integers (e.g., C<0123>).

=head3 ARGUMENTS

=over

=item VAL - integer

Required. The integer to check.

=item MAX - integer

Required. The maximum integer value to compare VAL to.

=item NAME - string

Optional. If provided, exceptions will be generated with a parameter name included.

=back

=head3 RETURNS

(empty) if the integer is a nonnegative value that is less than the MAX value.

=head3 THROWS

If the integer exceeds the MAX value.

If the integer is not a nonnegative integer value.

=cut

sub unsigned_and_less_than {
    my ( $val, $max, $name ) = @_;

    if ( !length $val || $val =~ m<\A\s+\z> ) {
        die Cpanel::Exception::create('Empty') if !$name;
        die Cpanel::Exception::create( 'Empty', [ name => $name ] );
    }

    my $minus_at = rindex( $val, '-' );
    if ( $minus_at == 0 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'This value must be a nonnegative integer, not “[_1]”.',       [$val] ) if !$name;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value must be a nonnegative integer, not “[_2]”.', [ $name, $val ] );
    }

    _verify_numerals_only( $val, $name );

    _verify_canonical( $val, $name );

    if ( _a_exceeds_b( $val, $max ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” exceeds the maximum allowed value ([_2]).', [ $val, $max ] ) if !$name;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value “[_2]” exceeds the maximum allowed value ([_3]).', [ $name, $val, $max ] );
    }

    return;
}

=head1 FUNCTION

=head2 unsigned( VAL, NAME )

As you might expect … it throws if VAL is invalid; otherwise
it returns (empty).

The thrown exception is an instance of L<Cpanel::Exception::InvalidParameter>
with a string that describes what’s wrong with the input.

This rejects leading C<0> integers (e.g., C<0123>).

=head3 ARGUMENTS

=over

=item VAL - integer

Required. The integer to check.

=item NAME - string

Optional. If provided, exceptions will be generated with a parameter name included.

=back

=head3 RETURNS

(empty) if the integer is a nonnegative value.

=head3 THROWS

If the integer is not a nonnegative integer value.

=cut

sub unsigned {
    my ( $val, $name ) = @_;

    unsigned_and_less_than( $val, $Cpanel::OSSys::Bits::MAX_NATIVE_UNSIGNED, $name );

    return;
}

sub _verify_canonical {
    my ( $val, $name ) = @_;

    my $is_bad;

    if ( index( $val, '0' ) == 0 ) {
        $is_bad = ( $val ne '0' );
    }
    elsif ( index( $val, '-0' ) == 0 ) {
        $is_bad = 1;
    }

    if ($is_bad) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is invalid because this system rejects integers that begin with “[_2]”.', [ $val, '0' ] ) if !$name;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value “[_2]” is invalid because this system rejects integers that begin with “[_3]”.', [ $name, $val, '0' ] );
    }

    return;
}

sub _a_exceeds_b {
    my ( $a, $b ) = @_;

    #NB: -1 means the left side is the lower value.

    my $len_cmp = length($a) <=> length($b);

    if ( $len_cmp > 0 ) {
        return 1;
    }
    elsif ( $len_cmp == 0 ) {
        my $sort = $a cmp $b;
        return ( $sort > 0 );
    }

    return 0;
}

sub _verify_numerals_only {
    my ( $val, $name ) = @_;

    if ( my $bad_count = ( $val =~ tr<0-9><>c ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid nonnegative integer because it contains [quant,_2,invalid character,invalid characters].', [ $val, $bad_count ] ) if !$name;
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” value “[_2]” is not a valid nonnegative integer because it contains [quant,_3,invalid character,invalid characters].', [ $name, $val, $bad_count ] );
    }

    return;
}

1;
