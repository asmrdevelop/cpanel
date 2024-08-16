package Cpanel::APICommon::DNS;

# cpanel - Cpanel/APICommon/DNS.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::APICommon::DNS

=head1 SYNOPSIS

    my $err = get_mass_edit_add_error($specimen);

    my $err = get_mass_edit_edit_error($specimen);

    my $err = get_mass_edit_remove_error($specimen);

=head1 DESCRIPTION

This module stores common logic for DNS APIs in cPanel and WHM.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $err = get_mass_edit_add_error( $REFERENCE )

Returns a human-readable string that describes what’s wrong with
$REFERENCE, or undef if there’s nothing wrong.

=cut

sub get_mass_edit_add_error ($item) {
    return _get_add_edit_error(
        $item,   'add',
        'dname', 'ttl', 'record_type', 'data',
    );
}

=head2 $err = get_mass_edit_edit_error( $REFERENCE )

Like C<get_mass_edit_add_error()> but for C<edit> submissions.

=cut

sub get_mass_edit_edit_error ($item) {
    return _get_add_edit_error(
        $item, 'edit',
        'line_index', 'dname', 'ttl', 'record_type', 'data',
    );
}

=head2 $err = get_mass_edit_remove_error( $SPECIMEN )

Like C<get_mass_edit_add_error()> but for C<remove> submissions.

=cut

sub get_mass_edit_remove_error ($item) {
    if ( $item !~ m<\A[0-9]+\z> ) {
        return locale()->maketext( 'Each “[_1]” must be a nonnegative integer.', 'remove' );
    }

    return undef;
}

#----------------------------------------------------------------------

sub _get_add_edit_error ( $item, $name, @needed ) {
    my $err = _not_hash_err( $item, $name );

    $err ||= _missing_piece_err( $item, $name, @needed );

    $err ||= _data_not_array_err($item);

    return $err;
}

sub _not_hash_err ( $item, $name ) {
    if ( 'HASH' ne ref $item ) {
        return locale()->maketext( 'Each “[_1]” must be an object.', $name );
    }

    return undef;
}

sub _data_not_array_err ($item) {
    if ( 'ARRAY' ne ref $item->{'data'} ) {
        return locale()->maketext( '“[_1]” must be an array.', 'data' );
    }

    return undef;
}

sub _missing_piece_err ( $item, $name, @pieces ) {
    my @missing = grep { !length $item->{$_} } @pieces;

    if (@missing) {
        return locale()->maketext( 'Each “[_1]” requires [list_and_quoted,_2].', $name, \@pieces );
    }

    return undef;
}

1;
