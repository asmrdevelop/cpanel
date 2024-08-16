package Cpanel::NetSSLeay::X509_VERIFY_PARAM;

# cpanel - Cpanel/NetSSLeay/X509_VERIFY_PARAM.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::NetSSLeay::X509_VERIFY_PARAM - Verification parameters

=head1 SYNOPSIS

    my $vpm = Cpanel::NetSSLeay::X509_VERIFY_PARAM->new();

    $vpm->set_flags( Net::SSLeay::X509_V_FLAG_TRUSTED_FIRST() );

    $x509_store->set1_param($vpm);

=head1 DESCRIPTION

A wrapper around OpenSSL X509_VERIFY_PARAM objects.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::NetSSLeay::Base );

use constant {
    _new_func  => 'X509_VERIFY_PARAM_new',
    _free_func => 'X509_VERIFY_PARAM_free',
};

use Cpanel::NetSSLeay ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<OBJ>->set_flags( $FLAGS_NUMBER )

Sets flags (as a number) on I<OBJ>. See L</SYNOPSIS> above for an example.

=cut

sub set_flags ( $self, $flags_num ) {
    Cpanel::NetSSLeay::do( 'X509_VERIFY_PARAM_set_flags', $self->PTR(), $flags_num );

    return $self;
}

1;
