package Whostmgr::API::1::Utils;

# cpanel - Whostmgr/API/1/Utils.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Utils - arg processing, and other delights

=head1 SYNOPSIS

    my $val = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'the_name' );

    #i.e., argument is optional but must have length if given
    my $val = Whostmgr::API::1::Utils::get_length_argument( $args, 'the_name' );

    #empty is ok, but must be defined
    my $val = Whostmgr::API::1::Utils::get_required_argument( $args, 'the_name' );

    #Useful for grabbing multiple occurrences of the same parameter
    #from the form.
    my @vals = Whostmgr::API::1::Utils::get_arguments( $args, 'the_name' );
    my @vals = Whostmgr::API::1::Utils::get_length_required_arguments( $args, 'the_name' );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    Whostmgr::API::1::Utils::set_metadata_not_ok($metadata, $reason);

=head1 DESCRIPTION

This module exists to simplify a few matters related to writing WHM API v1
calls. The examples above illustrate correct usage.

=cut

use strict;
use warnings;

use Cpanel::Context     ();
use Cpanel::Exception   ();
use Cpanel::Form::Param ();

sub get_required_argument {
    my ( $args, $arg ) = @_;

    my $value = $args->{$arg};
    if ( !defined $value ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $arg ] );
    }

    return $value;
}

sub get_length_required_argument {
    my ( $args, $arg ) = @_;

    my $value = get_required_argument( $args, $arg );
    if ( !length $value ) {
        die Cpanel::Exception::create( 'Empty', [ name => $arg ] );
    }

    return $value;
}

# Returns an optional argument.  If it exists, then it must be a non-zero length
sub get_length_argument {
    my ( $args, $arg ) = @_;
    my $value = $args->{$arg};

    if ( defined $value && !length $value ) {
        die Cpanel::Exception::create( 'Empty', [ name => $arg ] );
    }

    return $value;
}

#----------------------------------------------------------------------

sub get_arguments {
    my ( $args, $arg ) = @_;

    Cpanel::Context::must_be_list();

    return Cpanel::Form::Param->new( { parseform_hr => $args } )->param($arg);
}

sub get_length_arguments {
    my ( $args, $arg ) = @_;

    Cpanel::Context::must_be_list();

    my @values = get_arguments( $args, $arg );

    if ( grep { !length } @values ) {
        die Cpanel::Exception::create( 'Empty', 'The “[_1]” arguments cannot be empty.', [$arg] );
    }

    return @values;
}

sub get_length_required_arguments {
    my ( $args, $arg ) = @_;

    Cpanel::Context::must_be_list();

    my @values = get_length_arguments( $args, $arg );

    if ( !@values ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Provide at least one “[_1]” argument.', [$arg] );
    }

    return @values;
}

sub map_length_required_multiple_to_key_values {
    my ( $args, $key, $value ) = @_;

    my @keys   = get_length_required_arguments( $args, $key );
    my @values = get_length_required_arguments( $args, $value );

    if ( scalar @keys != scalar @values ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Provide the same number of “[_1]” and “[_2]” arguments.', [ $key, $value ] );
    }

    my %key_to_value_map;
    @key_to_value_map{@keys} = @values;
    return \%key_to_value_map;
}

=head2 map_length_multiple_to_key_values

Creates a mapping between two API arguments using one argument as a key and the other as a value

For example if passed the arguments:

    key1=a key2=b key3=c value1=d value2=e value3=f

Then passing “key” as C<$key> and “value” as C<$value> will return:

    { "a" => "d", "b" => "e", "c" => "f" }

=over

=item Input

=over

=item C<$args>

The C<HASHREF> containing the arguments that were passed to the API.

=item C<$key>

A string specifying which arguments to use as the key.

=item C<$value>

A string specifying which arguments to use as the values.

=back

=item Output

=over

Returns a HASHREF of the key/value pairs defined by the arguments.

=back

=back

=cut

sub map_length_multiple_to_key_values {
    my ( $args, $key, $value ) = @_;

    my @keys   = get_length_arguments( $args, $key );
    my @values = get_arguments( $args, $value );

    if ( scalar @keys != scalar @values ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'Provide the same number of “[_1]” and “[_2]” arguments.', [ $key, $value ] );
    }

    my %key_to_value_map;
    @key_to_value_map{@keys} = @values;
    return \%key_to_value_map;
}

#----------------------------------------------------------------------

sub set_metadata_ok {
    my ($metadata) = @_;

    @{$metadata}{qw(result reason)} = qw(1 OK);

    return;
}

sub set_metadata_not_ok {
    my ( $metadata, $reason ) = @_;
    @{$metadata}{qw(result reason)} = ( 0, $reason );
    return;
}

1;
