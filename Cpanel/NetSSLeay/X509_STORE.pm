package Cpanel::NetSSLeay::X509_STORE;

# cpanel - Cpanel/NetSSLeay/X509_STORE.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::NetSSLeay::X509_STORE

=head1 DESCRIPTION

A simple wrapper around Net::SSLeay’s X509_STORE objects.

Subclasses L<Cpanel::NetSSLeay::Base>.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::NetSSLeay::Base );

use constant {
    _new_func  => 'X509_STORE_new',
    _free_func => 'X509_STORE_free',
};

use Cpanel::NetSSLeay ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<OBJ>->add_cert( $X509_OBJ )

$X509_OBJ is a L<Cpanel::NetSSLeay::X509> instance. Returns I<OBJ>.

=cut

sub add_cert {
    my ( $self, $x509_obj ) = @_;

    Cpanel::NetSSLeay::do( 'X509_STORE_add_cert', $self->PTR(), $x509_obj->PTR() );

    return $self;
}

=head2 $obj = I<OBJ>->load_locations( $FILE [, $DIR] )

Returns I<OBJ>.

=cut

sub load_locations {
    my ( $self, $file, $dir ) = @_;

    Cpanel::NetSSLeay::do( 'X509_STORE_load_locations', $self->PTR(), $file, $dir );

    return $self;
}

=head2 $obj = I<OBJ>->set1_param( $VERIFY_PARAM_OBJ )

$VERIFY_PARAM is a L<Cpanel::NetSSLeay::X509_VERIFY_PARAM> instance.

This will call $VERIFY_PARAM_OBJ’s C<leak()> on success to prevent
a double-free error.

Returns I<OBJ>.

=cut

sub set1_param ( $self, $verify_params_obj ) {
    my $need_class = 'Cpanel::NetSSLeay::X509_VERIFY_PARAM';

    if ( !$verify_params_obj->isa($need_class) ) {
        die "Parameter must be $need_class instance, not $verify_params_obj";
    }

    Cpanel::NetSSLeay::do( 'X509_STORE_set1_param', $self->PTR(), $verify_params_obj->PTR() );

    $verify_params_obj->leak();

    return $self;
}

=head2 $obj = I<OBJ>->set_verify_callback( $TODO_CR, $OTHER )

Returns I<OBJ>.

NOTE: This makes OpenSSL leak memory. The leak is worse if you wrap the
X509_STORE_CTX of the callback parameters in an instance of our Perl
X509_STORE_CTX.pm class, so we leave it unadorned here. Note that it’ll be
the same STORE_CTX that gets used to fire off OpenSSL’s X509_verify_cert()
method (which is in our X509_STORE_CTX.pm), so you probably don’t even need
that parameter.

=cut

sub set_verify_callback {
    my ( $self, $todo_cr, $other ) = @_;

    Cpanel::NetSSLeay::do(
        'X509_STORE_set_verify_callback',
        $self->PTR(),

        #The callback that goes to Net::SSLeay should return 1; otherwise
        #the validity check won’t look for other problems on the certificate.
        sub { $todo_cr->(@_); 1 },

        $other,
    );

    return $self;
}

1;
