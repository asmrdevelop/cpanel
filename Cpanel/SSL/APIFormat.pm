package Cpanel::SSL::APIFormat;

# cpanel - Cpanel/SSL/APIFormat.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::APIFormat

=head1 SYNOPSIS

    $api_ret = Cpanel::SSL::APIFormat::convert_cert_obj_to_api_return($cert_obj);

=head1 DESCRIPTION

This module contains logic to mimic the return structure that various APIs
expect.

=cut

#----------------------------------------------------------------------

use Cpanel::SSLStorage::Utils ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $hr = convert_cert_obj_to_api_return( $CERT_OBJ )

$CERT_OBJ is a L<Cpanel::SSL::Objects::Certificate> instance. The return
is a reference to a hash that contains the following. Unless otherwise
indicated, these all match the output of $CERT_OBJ’s equivalent method:

=over

=item * C<id> - from C<Cpanel::SSLStorage::Utils::make_certificate_id()>

=item * C<issuer.commonName> - from the C<issuer()> method

=item * C<issuer.organizationName> - from the C<issuer()> method

=item * C<subject.commonName> - from the C<subject()> method

=item * C<issuer_text>

=item * C<subject_text>

=item * C<is_self_signed>

=item * C<domains>

=item * C<modulus>

=item * C<modulus_length>

=item * C<not_after>

=item * C<not_before>

=item * C<signature_algorithm>

=item * C<validation_type>

=back

=cut

#mimic the old SSLStorage return items
sub convert_cert_obj_to_api_return {
    my ($cert_obj) = @_;

    my ( $ok, $id ) = Cpanel::SSLStorage::Utils::make_certificate_id( $cert_obj->text() );
    die "make cert ID: $id" if !$ok;

    my $parsed_hr = $cert_obj->parsed();

    my %api_return;

    @api_return{
        'id',
        _CERT_OBJ_API_RETURNS(),
        qw(
          issuer.commonName
          issuer.organizationName
          issuer_text
          subject.commonName
          subject_text
        ),
      } = (
        $id,
        @{$parsed_hr}{ _CERT_OBJ_API_RETURNS() },
        @{ $parsed_hr->{'issuer'} }{ 'commonName', 'organizationName' },
        $cert_obj->issuer_text(),
        $parsed_hr->{'subject'}{'commonName'},
        $cert_obj->subject_text(),
      );

    return \%api_return;
}

use constant _CERT_OBJ_API_RETURNS => qw(
  domains
  is_self_signed
  modulus
  modulus_length
  not_after
  not_before
  signature_algorithm
  validation_type
);

1;
