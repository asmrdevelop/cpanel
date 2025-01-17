package Crypt::OpenSSL::DSA;

use strict;
use warnings;

use XSLoader;

our $VERSION = '0.20';

XSLoader::load 'Crypt::OpenSSL::DSA', $VERSION;

sub read_pub_key_str {
  my ($class, $key_str) = @_;
  $class->_load_key(0, $key_str);
}

sub read_priv_key_str {
  my ($class, $key_str) = @_;
  $class->_load_key(1, $key_str);
}

1;
__END__

=head1 NAME

Crypt::OpenSSL::DSA - Digital Signature Algorithm using OpenSSL

=head1 SYNOPSIS

  use Crypt::OpenSSL::DSA;

  # generate keys and write out to PEM files
  my $dsa = Crypt::OpenSSL::DSA->generate_parameters( 512 );
  $dsa->generate_key;
  $dsa->write_pub_key( $filename );
  $dsa->write_priv_key( $filename );

  # using keys from PEM files
  my $dsa_priv = Crypt::OpenSSL::DSA->read_priv_key( $filename );
  my $sig      = $dsa_priv->sign($message);
  my $dsa_pub  = Crypt::OpenSSL::DSA->read_pub_key( $filename );
  my $valid    = $dsa_pub->verify($message, $sig);

  # using keys from PEM strings
  my $dsa_priv = Crypt::OpenSSL::DSA->read_priv_key_str( $key_string );
  my $sig      = $dsa_priv->sign($message);
  my $dsa_pub  = Crypt::OpenSSL::DSA->read_pub_key_str( $key_string );
  my $valid    = $dsa_pub->verify($message, $sig);

=head1 DESCRIPTION

Crypt::OpenSSL::DSA implements the DSA
(Digital Signature Algorithm) signature verification system.

It is a thin XS wrapper to the DSA functions contained in the 
OpenSSL crypto library, located at http://www.openssl.org

=head1 CLASS METHODS

=over 4

=item $dsa = Crypt::OpenSSL::DSA->generate_parameters( $bits, $seed );

Returns a new DSA object and generates the p, q and g
parameters necessary to generate keys.

bits is the length of the prime to be generated; the DSS allows a maximum of 1024 bits.

=item $dsa = Crypt::OpenSSL::DSA->read_params( $filename );

Reads in a parameter PEM file and returns a new DSA object with the p, q and g
parameters necessary to generate keys.

=item $dsa = Crypt::OpenSSL::DSA->read_pub_key( $filename );

Reads in a public key PEM file and returns a new DSA object that can be used
to verify DSA signatures.

=item $dsa = Crypt::OpenSSL::DSA->read_priv_key( $filename );

Reads in a private key PEM file and returns a new DSA object that can be used
to sign messages.

=item $dsa = Crypt::OpenSSL::DSA->read_pub_key_str( $key_string );

Reads in a public key PEM string and returns a new DSA object that can be used
to verify DSA signatures.
The string should include the -----BEGIN...----- and -----END...----- lines.

=item $dsa = Crypt::OpenSSL::DSA->read_priv_key_str( $key_string );

Reads in a private key PEM string and returns a new DSA object that can be used
to sign messages.
The string should include the -----BEGIN...----- and -----END...----- lines.

=back

=head1 OBJECT METHODS

=over 4

=item $dsa->generate_key;

Generates private and public keys, assuming that $dsa is the return
value of generate_parameters.

=item $sig_size = $dsa->get_sig_size( );

Returns the maximum size of an ASN.1 encoded DSA signature for key
dsa in bytes.

 512-bit keys = 48
1024-bit keys = 48
2024-bit keys = 72
3072-bit keys = 72

ASN.1 dsa signatures consist of:

Sequence 1-byte (0x30)
Length   1-byte
Integer  1-byte (0x02)
Length   1-byte (0x14) = 20
r       20-bytes or 21-bytes
Integer  1-byte (0x02)
Length   1-byte (0x14) = 20
s       20-bytes or 21-bytes

30
2C
02
14
6C.70.50.7C.93.A8.B5.EC.1E.A1.5E.C5.73.AA.0F.EA.4D.BE.42.7A
02
14
4E.AD.E6.BB.72.54.92.30.2B.03.AB.53.5D.3D.6E.88.B8.AA.D6.30

Note that the above signature is 46 bytes long - the extra two bytes are used
only when r and/or s are larger than or equal to 2^159.  The extra bytes are
used to distinguish positive from negative values.

All that to say if you are using get_sig_size() to determine the size of r + s
depending on the size of the key you can subtract 8 bytes for the ASN.1 overhead.

=item $sig = $dsa->sign( $message );

Signs $message, returning the signature.  Note that $meesage cannot exceed
20 characters in length.

$dsa is the signer's private key.

=item $sig_obj = $dsa->do_sign( $message );

Similar to C<sign>, but returns a L<Crypt::OpenSSL::DSA::Signature> object.

=item $valid = $dsa->verify( $message, $sig );

Verifies that the $sig signature for $message is valid.

$dsa is the signer's public key.

Note: it croaks if the underlying library call returns error (-1).

=item $valid = $dsa->do_verify( $message, $sig_obj );

Similar to C<verify>, but uses a L<Crypt::OpenSSL::DSA::Signature> object.

Note: it croaks if the underlying library call returns error (-1).

=item $dsa->write_params( $filename );

Writes the parameters into a PEM file.

=item $dsa->write_pub_key( $filename );

Writes the public key into a PEM file.

=item $dsa->write_priv_key( $filename );

Writes the private key into a PEM file.

=item $p = $dsa->get_p, $dsa->set_p($p)

Gets/sets the prime number in binary format.

=item $q = $dsa->get_q, $dsa->set_q($q)

Gets/sets the subprime number (q | p-1) in binary format.

=item $g = $dsa->get_g, $dsa->set_g($g)

Gets/sets the generator of subgroup in binary format.

=item $pub_key = $dsa->get_pub_key, $dsa->set_pub_key($pub_key)

Gets/sets the public key (y = g^x) in binary format.

=item $priv_key = $dsa->get_priv_key, $dsa->set_priv_key($priv_key)

Gets/sets the private key in binary format.

=back

=head1 NOTES

L<Crpyt::DSA> is a more mature Perl DSA module, but can be difficult to
install, because of the L<Math::Pari> requirement.

Comments, suggestions, and patches welcome.

=head1 AUTHOR

T.J. Mather, E<lt>tjmather@maxmind.comE<gt>

=head1 COPYRIGHT

Copyright (c) 2002 T.J. Mather.  Crypt::OpenSSL::DSA is free software;
you may redistribute it and/or modify it under the same terms as Perl itself. 

Paid support is available directly from the author of this package.
Please see L<http://www.maxmind.com/app/opensourceservices> for more details.

=head1 SEE ALSO

L<Crypt::OpenSSL::DSA::Signature>

L<Crypt::DSA>, L<Crypt::OpenSSL::RSA>

L<Net::DNS::SEC>

=cut
