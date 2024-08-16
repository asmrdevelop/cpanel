package Cpanel::NetSSLeay::X509_STORE_CTX;

# cpanel - Cpanel/NetSSLeay/X509_STORE_CTX.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::NetSSLeay::Base );

use constant {
    _new_func  => 'X509_STORE_CTX_new',
    _free_func => 'X509_STORE_CTX_free',
};

use Cpanel::NetSSLeay              ();
use Cpanel::NetSSLeay::StackOfX509 ();

my %INSTANCE_BIO;
my %INSTANCE_UNTRUSTED_STACK;

#----------------------------------------------------------------------
# A simple wrapper around Net::SSLeay’s X509_STORE_CTX objects that ensures
# we don’t neglect to do X509_STORE_CTX_free().
#----------------------------------------------------------------------

sub set_bio {
    my ( $self, $bio_obj ) = @_;

    $INSTANCE_BIO{$self} = $bio_obj;

    return $self;
}

sub init {
    my ( $self, $store_obj, $x509_obj, @untrusted ) = @_;

    my $bio = $INSTANCE_BIO{$self} or die 'set_bio() first!';

    my $untrusted_stack = Cpanel::NetSSLeay::StackOfX509->new( $bio, @untrusted );

    #Keep this around for the certificate verification.
    #Once init() gets called again, this will be DESTROY()ed.
    $INSTANCE_UNTRUSTED_STACK{$self} = $untrusted_stack;

    return Cpanel::NetSSLeay::do(
        'X509_STORE_CTX_init',
        $self->PTR(),
        $store_obj->PTR(),
        $x509_obj->PTR(),
        $untrusted_stack->PTR(),
    );
}

#NOTE: This breaks the naming pattern because the OpenSSL function is named
#inconsistently: ordinarily the function name prefix identifies the type
#of the first parameter; in this case, though, OpenSSL’s function starts
#with X509 rather than X509_STORE_CTX. This inconsistency seems worth
#rectifying here since it wouldn’t make sense to create this method on the
#X509 class.
sub verify_cert {
    return scalar Cpanel::NetSSLeay::do( 'X509_verify_cert', $_[0]->PTR() );
}

sub cleanup {
    return Cpanel::NetSSLeay::do( 'X509_STORE_CTX_cleanup', $_[0]->PTR() );
}

sub get_current_cert {
    if ( my $x509 = Cpanel::NetSSLeay::do( 'X509_STORE_CTX_get_current_cert', $_[0]->PTR() ) ) {
        require Cpanel::NetSSLeay::X509;
        return Cpanel::NetSSLeay::X509->new_wrap($x509);
    }
    return;
}

sub get_error {
    return Cpanel::NetSSLeay::do( 'X509_STORE_CTX_get_error', $_[0]->PTR() );
}

sub get_error_depth {
    return Cpanel::NetSSLeay::do( 'X509_STORE_CTX_get_error_depth', $_[0]->PTR() );
}

sub DESTROY {

    #It is very important that these be *delete*, not just undef!
    #(Otherwise these hashes keep growing in size, and we have a
    #memory leak.)
    delete $INSTANCE_UNTRUSTED_STACK{ $_[0] };
    delete $INSTANCE_BIO{ $_[0] };

    return $_[0]->SUPER::DESTROY();
}

1;
