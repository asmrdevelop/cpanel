package Cpanel::Exception::API::UAPI;

# cpanel - Cpanel/Exception/API/UAPI.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::API::UAPI

=head1 DESCRIPTION

This exception class represents failed UAPI calls.

=head1 ATTRIBUTES

=over

=item * C<module> - The name of the UAPI module (e.g., C<Email>) that was called

=item * C<function_name> - The name (e.g., C<list_pops>) of the API call that
failed.

=item * C<result> - Instance of L<Cpanel::Result>
that encapsulates the API’s response.

=back

=cut

#----------------------------------------------------------------------

use parent qw(Cpanel::Exception);

use Cpanel::LocaleString ();

#----------------------------------------------------------------------

sub _default_phrase ( $self, $metadata_hr ) {

    my $module = $self->get('module');
    my $fn     = $self->get('function_name');
    my $err    = $self->get('result')->errors_as_string();

    return Cpanel::LocaleString->new(
        'The [asis,UAPI] call “[_1]” failed: [_2]',
        "${module}::$fn", $err,
    );
}

1;
