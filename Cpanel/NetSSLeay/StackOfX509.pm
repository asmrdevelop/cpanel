package Cpanel::NetSSLeay::StackOfX509;

# cpanel - Cpanel/NetSSLeay/StackOfX509.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::NetSSLeay::StackOfX509

=head1 SYNOPSIS

    my $stack = Cpanel::NetSSLeay::StackOfX509->new( $bio, @certificates_pem )

=head1 DESCRIPTION

This object encapsulates OpenSSL’s C<STACK_OF(X509)> type with automatic
garbage collection via DESTROY.

This class is needed (rather than individual L<Cpanel::NetSSLeay::X509>
instances) because C<STACK_OF(X509)> is garbage-collected as a single unit.

BTW: This class is not named C<X509_STACK> because that name, unlike
C<X509_STORE> et al., doesn’t exist in OpenSSL.

=cut

use Cpanel::NetSSLeay ();
use Net::SSLeay       ();

use parent qw( Cpanel::NetSSLeay::Base );

use constant {
    _new_func  => 'get_stack_of_X509',
    _free_func => 'free_stack_of_X509',
};

=head1 METHODS

=head2 I<CLASS>->new( BIO_OBJ, PEM1, PEM2, .. )

BIO_OBJ is an instance of L<Cpanel::NetSSLeay::BIO>, and the PEM*
arguments are PEM representations of certificates.

=cut

sub new {
    my ( $class, $bio, @cert_pems ) = @_;

    my @x509_ptrs = map {
        $bio->write($_);
        Cpanel::NetSSLeay::do( 'PEM_read_bio_X509', $bio->PTR() );
    } @cert_pems;

    return $class->SUPER::new(@x509_ptrs);
}

1;
