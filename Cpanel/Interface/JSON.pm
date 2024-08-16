package Cpanel::Interface::JSON;

# cpanel - Cpanel/Interface/JSON.pm                Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::JSON ();

=encoding utf8

=head1 NAME

Cpanel::Interface::JSON - interface for JSON helpers

=head1 SYNOPSIS

    package MyPackage;

    use parent qw{ Cpanel::Interface::JSON }


    sub my_function( $self ) {

        $self->to_json( { my => 'data' } );

        $self->from_json( '{my: "data"}' );

    }

=head2 $self->to_json( $data )

Convert data to JSON

=cut

sub to_json ( $, $data ) {
    return scalar Cpanel::JSON::canonical_dump($data);
}

=head2 $self->from_json( $str )

Parse JSON string.
Returns 'undef' on errors.

=cut

sub from_json ( $, $str ) {
    return unless defined $str;
    return eval { Cpanel::JSON::Load($str) };
}

1;
