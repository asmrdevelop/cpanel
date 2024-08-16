package Cpanel::SSL::Hash;

# cpanel - Cpanel/SSL/Hash.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Hash - Certificate hashing

=head1 SYNOPSIS

    my $hash = Cpanel::SSL::Hash->new();

    my $subject_hash = $hash->X509_subject_name_hash( $pem );

=cut

use strict;
use warnings;

use Cpanel::LoadModule ();

sub new {
    my ($class) = @_;

    Cpanel::LoadModule::load_perl_module('Net::SSLeay')             if !$INC{'Net/SSLeay.pm'};
    Cpanel::LoadModule::load_perl_module('Cpanel::NetSSLeay::BIO')  if !$INC{'Cpanel/NetSSLeay/BIO.pm'};
    Cpanel::LoadModule::load_perl_module('Cpanel::NetSSLeay::X509') if !$INC{'Cpanel/NetSSLeay/X509.pm'};

    Net::SSLeay::initialize();

    my $self = bless {
        '_bio_obj' => Cpanel::NetSSLeay::BIO->new_s_mem(),
    }, $class;

    return $self;
}

=head2 X509_subject_name_hash

A wrapper around Net::SSLeay::X509_subject_name_hash.  This provides the same function as openssl x509 -in -hash

=over 2

=item Input

=over 3

=item C<SCALAR>

   A certificate in PEM format.

=back

=item Output

=over 3

=item C<SCALAR>

    The hash of the subject name as defined by openssl.

=back

=back

=cut

sub X509_subject_name_hash {
    my ( $self, $pem ) = @_;

    my $cert_to_check = Cpanel::NetSSLeay::X509->new( $self->{'_bio_obj'}, $pem );

    return sprintf( "%08lx", $cert_to_check->X509_subject_name_hash() );
}

1;
