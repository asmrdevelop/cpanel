package Cpanel::NetSSLeay::CTX;

# cpanel - Cpanel/NetSSLeay/CTX.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Net::SSLeay ();

use parent qw( Cpanel::NetSSLeay::Base );

use constant {
    _new_func  => 'CTX_new',
    _free_func => 'CTX_free',
};

use Cpanel::LoadModule ();
use Cpanel::NetSSLeay  ();

=encoding utf-8

=head1 NAME

Cpanel::NetSSLeay::CTX - Write Net::SSLeay’s CTX objects

=head1 SYNOPSIS

    use Cpanel::NetSSLeay::CTX;

    my $ctx_obj = Cpanel::NetSSLeay::CTX->new();
    $ctx_obj->set_options('ALL');
    $ctx_obj->use_PrivateKey_file( $key, 'PEM' );
    $ctx_obj->use_certificate_chain_file( $cert );    #in PEM format

    my $ssl_obj = Cpanel::NetSSLeay::SSL->new( $ctx_obj );

=head1 DESCRIPTION

A simple wrapper around Net::SSLeay’s CTX objects that ensures we don’t
neglect to do CTX_free().

=cut

=head2 set_cipher_list

A wrapper around Net::SSLeay::CTX_set_cipher_list

=over 2

=item Input

=over 3

=item C<SCALAR>

An openssl cipher list string.

=back

=item Output

=over

=item Returns from Net::SSLeay::CTX_set_cipher_list

=back

=back

=cut

sub set_cipher_list {
    my ( $self, $list_txt ) = @_;

    return Cpanel::NetSSLeay::do( 'CTX_set_cipher_list', $self->PTR(), $list_txt );
}

=head2 get_cert_store

A wrapper around Net::SSLeay::CTX_get_cert_store

=head3 Input

None

=head3 Output

Returns a Cpanel::NetSSLeay::X509_STORE object

=cut

sub get_cert_store {
    my ($self) = @_;

    my $store_ptr = Cpanel::NetSSLeay::do( 'CTX_get_cert_store', $self->PTR() );

    Cpanel::LoadModule::load_perl_module('Cpanel::NetSSLeay::X509_STORE');

    return Cpanel::NetSSLeay::X509_STORE->new_wrap($store_ptr);
}

=head2 set_options

A wrapper around Net::SSLeay::CTX_set_options

=head3 Input

An array of options that match the OP_ constants in Net::SSLeay.

=head3 Output

Returns from Net::SSLeay::CTX_set_options

=cut

sub set_options {
    my ( $self, @options ) = @_;

    my $opts = 0;
    foreach my $opt (@options) {
        my $const = "OP_$opt";

        $opts |= Net::SSLeay->$const();
    }

    return Cpanel::NetSSLeay::do(
        'CTX_set_options',
        $self->PTR(),
        $opts
    );
}

=head2 use_PrivateKey_file

A wrapper around Net::SSLeay::CTX_use_PrivateKey_file

=head3 Input

=over

=item C<SCALAR>

The path to the private key file

=item C<SCALAR>

The format of the private key file (C<PEM> or C<ASN1>)

=back

=head3 Output

Returns from Net::SSLeay::CTX_use_PrivateKey_file

=cut

sub use_PrivateKey_file {
    my ( $self, $path, $type ) = @_;

    my $const = "FILETYPE_$type";

    return Cpanel::NetSSLeay::do(
        'CTX_use_PrivateKey_file',
        $self->PTR(),
        $path,
        Net::SSLeay->$const(),
    );
}

=head2 use_certificate_chain_file

A wrapper around Net::SSLeay::CTX_use_certificate_chain_file

=head3 Input

=over

=item C<SCALAR>

The path to the certificate chain file in PEM format.
The certificate chain must be ordered, leaf-first.

=back

=head3 Output

Returns from Net::SSLeay::CTX_use_certificate_chain_file

=cut

sub use_certificate_chain_file {
    my ( $self, $pem_path ) = @_;

    return Cpanel::NetSSLeay::do(
        'CTX_use_certificate_chain_file',
        $self->PTR(),
        $pem_path,
    );
}

=head2 set_tmp_dh

A wrapper around Net::SSLeay::CTX_set_tmp_dh

=head3 Input

=over

=item C<SCALAR>

A pointer to the DH params

=back

=head3 Output

Returns from Net::SSLeay::CTX_set_tmp_dh

=cut

sub set_tmp_dh {
    my ( $self, $dh ) = @_;
    return Cpanel::NetSSLeay::do(
        'CTX_set_tmp_dh',
        $self->PTR(),
        $dh
    );
}

=head2 set_tmp_ecdh

A wrapper around Net::SSLeay::CTX_set_tmp_ecdh

=head3 Input

=over

=item C<Cpanel::NetSSLeay::EC_KEY>

A Cpanel::NetSSLeay::EC_KEY object that points to the ECDH params

=back

=head3 Output

Returns from Net::SSLeay::CTX_set_tmp_ecdh

=cut

sub set_tmp_ecdh {
    my ( $self, $ec_key_obj ) = @_;
    return Cpanel::NetSSLeay::do(
        'CTX_set_tmp_ecdh',
        $self->PTR(),
        $ec_key_obj->PTR(),
    );
}

=head2 load_verify_locations

Wraps C<Net::SSLeay::CTX_load_verify_locations()>. See that function’s
documentation for input/output.

=cut

sub load_verify_locations ( $self, @args ) {
    return Cpanel::NetSSLeay::do(
        'CTX_load_verify_locations',
        $self->PTR(),
        @args,
    );
}

1;
