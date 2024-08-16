package Cpanel::APICommon::Error;

# cpanel - Cpanel/APICommon/Error.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::APICommon::Error - represent standard API error detail objects

=head1 FUNCTIONS

=head2 $hr = convert_to_payload( $TYPE, %OPTS )

Returns a hash reference that represents the given error object parameters.

TODO: Provide a reference that documents the returned structure.

=cut

sub convert_to_payload ( $type, %opts ) {
    return { type => $type, detail => %opts ? \%opts : undef };
}

=head2 get_type( $ERROR_OBJ )

Returns a string representation of the error type, for use in convert_to_paylod(). This
method only accepts blessed objects or it will return an empty string.

=cut

sub get_type ($error) {
    require Scalar::Util;
    return unless Scalar::Util::blessed($error);

    if ( $error->can('get') ) {
        my $get_result = $error->get('type');
        return $get_result if $get_result;
    }

    return ref $error;
}

1;
