package Cpanel::NetSSLeay::X509;

# cpanel - Cpanel/NetSSLeay/X509.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::NetSSLeay::Base );

use constant {
    _new_func  => 'X509_new',
    _free_func => 'X509_free',
};

use Cpanel::NetSSLeay ();

#----------------------------------------------------------------------
# A simple wrapper around Net::SSLeay’s X509 objects that ensures we don’t
# neglect to do X509_free().
#----------------------------------------------------------------------

sub new {
    my ( $class, $bio, $pem ) = @_;

    die "A BIO object is required" if !$bio->isa('Cpanel::NetSSLeay::BIO');

    $bio->write($pem);

    my $X509 = Cpanel::NetSSLeay::do( 'PEM_read_bio_X509', $bio->PTR() );

    return $class->new_wrap($X509)->_Set_To_Destroy();
}

sub get_pem {
    return Cpanel::NetSSLeay::do( 'PEM_get_string_X509', $_[0]->PTR() );
}

#Hopefully we won’t need the other formats that this function allows.
#cf. perldoc Net::SSLeay
sub get_subject_string {
    return Cpanel::NetSSLeay::do( 'X509_NAME_print_ex', Cpanel::NetSSLeay::do( 'X509_get_subject_name', $_[0]->PTR() ) );
}

# A simple wrapper around Net::SSLeay::X509_subject_name_hash
sub X509_subject_name_hash {
    my ($self) = @_;

    return Cpanel::NetSSLeay::do( 'X509_subject_name_hash', $self->PTR() );
}

#If it’s ever needed …
#sub get_serialNumber_hex {
#    my ($self) = @_;
#
#    my $rv           = Cpanel::NetSSLeay::do( 'X509_get_serialNumber',           $self->PTR() );
#    return Cpanel::NetSSLeay::do( 'P_ASN1_INTEGER_get_hex',          $rv );
#}

1;
