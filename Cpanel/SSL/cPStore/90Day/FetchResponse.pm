package Cpanel::SSL::cPStore::90Day::FetchResponse;

# cpanel - Cpanel/SSL/cPStore/90Day/FetchResponse.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::cPStore::90Day::FetchResponse

=head1 SYNOPSIS

See L<Cpanel::SSL::cPStore::90Day>.

=head1 DESCRIPTION

An object that represents the result of a successful call to cPStore’s
API to fetch a certificate.

B<IMPORTANT:> This object does B<NOT> always contain a certificate;
it can still indicate that the certificate order failed in some way.

=cut

#----------------------------------------------------------------------

use Cpanel::SSL::Utils ();

use Class::XSAccessor (
    getters => [
        'status',
        'status_message',
    ],
);

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

%OPTS are:

=over

=item * C<certificate> - The raw base64 of the DER-encoded certificate,
or undef if there is none.

=item * C<status> and C<status_message> - As from cPStore’s API.

=back

=cut

sub new ( $class, %opts ) {
    return bless \%opts, $class;
}

=head2 $yn = I<OBJ>->revoked()

Returns a boolean that indicates whether cPStore says the certificate
is revoked.

=cut

sub revoked ($self) {
    return $self->{'status'} eq 'revoked' ? 1 : 0;
}

=head2 $yn = I<OBJ>->revoked()

Returns a boolean that indicates whether cPStore says the certificate
order was rejected.

=cut

sub rejected ($self) {
    return $self->{'status'} eq 'rejected' ? 1 : 0;
}

=head2 $pem_or_undef = I<OBJ>->certificate_pem()

Returns either the PEM-encoded certificate, or undef if I<OBJ>
lacks such.

=cut

sub certificate_pem ($self) {
    my $pem = $self->{'certificate'};

    $pem &&= Cpanel::SSL::Utils::base64_to_pem( $pem, 'CERTIFICATE' );

    return $pem;
}

=head2 $msg = I<OBJ>->status()

Returns the C<status> given to C<new()>.

=head2 $msg = I<OBJ>->status_message()

Returns the C<status_message> given to C<new()>.

=head2 $str = I<OBJ>->to_string()

Returns a human-readable string that represents I<OBJ>’s contents.
The exact format is undefined. (Use this to facilitate debugging.)

=cut

sub to_string ($self) {
    require Cpanel::JSON;
    return Cpanel::JSON::canonical_dump( {%$self} );
}

1;
