package Cpanel::Exception::API::WHM1;

# cpanel - Cpanel/Exception/API/WHM1.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::API::WHM1

=head1 DESCRIPTION

This exception class represents failed WHM API v1 calls.

=head1 ATTRIBUTES

=over

=item * C<function_name> - The name (e.g., C<listaccts>) of the API call that
failed.

=item * C<result> - Instance of L<Whostmgr::API::1::Utils::Result>
that encapsulates the API’s response.

=back

=cut

#----------------------------------------------------------------------

use parent qw(Cpanel::Exception);

use Cpanel::LocaleString ();

#----------------------------------------------------------------------

sub _default_phrase ( $self, $metadata_hr ) {

    my $fn  = $self->get('function_name');
    my $err = $self->get('result')->get_error();

    return Cpanel::LocaleString->new(
        'The [asis,WHM API v1] call “[_1]” failed: [_2]',
        $fn, $err,
    );
}

1;
