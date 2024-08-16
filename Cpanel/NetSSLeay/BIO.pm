package Cpanel::NetSSLeay::BIO;

# cpanel - Cpanel/NetSSLeay/BIO.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::NetSSLeay::Base );

use constant {
    _new_func  => 'BIO_new',
    _free_func => 'BIO_free',
};

use Cpanel::NetSSLeay ();

#----------------------------------------------------------------------
# A simple wrapper around Net::SSLeay’s BIO objects that ensures we don’t
# neglect to do BIO_free().
#----------------------------------------------------------------------

sub new_s_mem {
    my ($class) = @_;

    return $class->SUPER::new( Cpanel::NetSSLeay::do('BIO_s_mem') );
}

sub new { ... }

*BIO = \&Cpanel::NetSSLeay::Base::PTR;    # PPI NO PARSE - use parent above

#----------------------------------------------------------------------
#Convenience methods

sub write {
    my ( $self, $data ) = @_;

    return Cpanel::NetSSLeay::do( 'BIO_write', $self->[0], $data );
}

sub PEM_read_bio_DHparams {
    my ($self) = @_;

    return Cpanel::NetSSLeay::do( 'PEM_read_bio_DHparams', $self->[0] );
}

1;
