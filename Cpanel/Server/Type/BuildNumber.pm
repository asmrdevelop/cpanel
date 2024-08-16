package Cpanel::Server::Type::BuildNumber;

# cpanel - Cpanel/Server/Type/BuildNumber.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::BuilderNumber - Helper module to determine products based on build numbers.

=head1 SYNOPSIS

    use Cpanel::Server::Type::BuildNumber ();

    my $is_current_cpanel = Cpanel::Server::Type::BuildNumber::is_current_build_cpanel();
    my $is_build_cpanel   = Cpanel::Server::Type::BuildNumber::is_cpanel_build_number('11.119.9999.0');

    my $is_current_wp2 = Cpanel::Server::Type::BuildNumber::is_current_build_wp2();
    my $is_build_wp2   = Cpanel::Server::Type::BuildNumber::is_cpanel_build_number('11.119.8999.0');

    my $is_same_as_current = Cpanel::Server::Type::BuildNumber::is_build_same_as_current_product('11.119.9999.0');

    my $display_string = Cpanel::Server::Type::BuildNumber::get_display_string_for_build_number('11.119.9999.0');

=head1 DESCRIPTION

This module is used to determine what type of product a build number corresponds to (e.g. regular cPanel, WP Squared, …)

=head1 FUNCTIONS

=cut

use utf8;

use cPstrict;

use Cpanel::Server::Type  ();
use Cpanel::Version::Tiny ();

our %PRODUCT_BUILDS = (
    'cpanel' => {
        display_string => "cPanel",
        development    => { min => 9000, max => 9999 },
        production     => 0,
    },
    'wp2' => {
        display_string => "WP Squared",
        development    => { min => 8000, max => 8999 },
        production     => 1,
    },
);

=head2 is_cpanel_build_number($build_number)

Determines if the build number provided is for a regular cPanel build.

=over

=item Input

=over

=item C<SCALAR>

The build number to check

=back

=item Output

=over

=item C<SCALAR>

Returns true if the build number is for a regular cPanel build, C<undef> otherwise.

=back

=back

=cut

sub is_cpanel_build_number ($build_number) {
    return _matches_build_numbers( $build_number, $PRODUCT_BUILDS{cpanel} );
}

=head2 is_current_build_cpanel()

Determines if the current build number is for a regular cPanel build.

=over

=item Input

=over

None

=back

=item Output

=over

=item C<SCALAR>

Returns true if the current build number is for a regular cPanel build, C<undef> otherwise.

NOTE: This will always return C<undef> on a developement sandbox. Consider carefully if using
the build number to determine the product type is really what you need and add an exception
for development sandboxes if necessary.

=back

=back

=cut

sub is_current_build_cpanel() {
    return _matches_build_numbers( $Cpanel::Version::Tiny::VERSION_BUILD, $PRODUCT_BUILDS{cpanel} );
}

=head2 is_wp2_build_number($build_number)

Determines if the build number provided is for a WP Squared build.

=over

=item Input

=over

=item C<SCALAR>

The build number to check

=back

=item Output

=over

=item C<SCALAR>

Returns true if the build number is for a WP Squared build, C<undef> otherwise.

=back

=back

=cut

sub is_wp2_build_number ($build_number) {
    return _matches_build_numbers( $build_number, $PRODUCT_BUILDS{wp2} );
}

=head2 is_current_build_wp2()

Determines if the current build number is for a WP Squared build.

=over

=item Input

=over

None

=back

=item Output

=over

=item C<SCALAR>

Returns true if the current build number is for a WP Squared build, C<undef> otherwise.

NOTE: This will always return C<undef> on a developement sandbox. Consider carefully if using
the build number to determine the product type is really what you need and add an exception
for development sandboxes if necessary.

=back

=back

=cut

sub is_current_build_wp2() {
    return _matches_build_numbers( $Cpanel::Version::Tiny::VERSION_BUILD, $PRODUCT_BUILDS{wp2} );
}

=head2 is_build_same_as_current_product ($build_number)

Determines if the provided build number represents the same product as the current build number.

=over

=item Input

=over

=item C<SCALAR>

The build number to check

=back

=item Output

=over

=item C<SCALAR>

Returns true if the provided build number is the same product as the current build number, C<undef> otherwise.

=back

=back

=cut

sub is_build_same_as_current_product ($build_number) {
    my $build_product   = _get_product_for_build_number($build_number);
    my $current_product = _get_product_for_build_number($Cpanel::Version::Tiny::VERSION_BUILD);
    return $build_product && $current_product && $build_product eq $current_product;
}

=head2 get_display_string_for_build_number ($build_number)

Retrieves a display string for the product represented by the provided build number

=over

=item Input

=over

=item C<SCALAR>

The build number to check

=back

=item Output

=over

=item C<SCALAR>

Returns a display string if the provided build number corresponds to a known product, C<undef> otherwise.

=back

=back

=cut

sub get_display_string_for_build_number ($build_number) {
    my $build_product = _get_product_for_build_number($build_number);
    return $build_product ? $PRODUCT_BUILDS{$build_product}{display_string} : undef;
}

sub _get_product_for_build_number ($build_number) {
    for my $product ( keys %PRODUCT_BUILDS ) {
        return $product if _matches_build_numbers( $build_number, $PRODUCT_BUILDS{$product} );
    }
    return;
}

sub _matches_build_numbers ( $build_number, $authorized_numbers ) {

    return if !length $build_number;

    my ( undef, $major, $minor ) = split /\./, $build_number, 4;

    if ( length $major && length $minor ) {

        my $number = $major % 2 == 0 ? $authorized_numbers->{production} : $authorized_numbers->{development};

        if ( ref($number) ) {
            return 1 if $minor >= $number->{min} && $minor <= $number->{max};
        }
        else {
            return 1 if $minor == $number;
        }

    }

    return;
}

1;
