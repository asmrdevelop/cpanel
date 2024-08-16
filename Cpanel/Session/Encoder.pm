package Cpanel::Session::Encoder;

# cpanel - Cpanel/Session/Encoder.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception ();

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = {};

    die Cpanel::Exception::create( 'MissingParameter', 'Provide the [asis,secret].' ) if !length $OPTS{'secret'};

    $self->{'secret'} = '' . $OPTS{'secret'};

    return bless $self, $class;
}

sub _check_data {
    my ($data_sr) = @_;

    die Cpanel::Exception::create( 'MissingParameter', 'Provide data.' ) if !length $$data_sr;

    return 1;
}

sub encode_data {
    my ( $self, $data ) = @_;

    die Cpanel::Exception::create( 'InvalidParameter', 'The final character cannot be a null byte.' ) if substr( $data, -1 ) eq "\0";

    _check_data( \$data );

    $self->_do_xor( \$data );

    return unpack 'h*', $data;
}

sub decode_data {
    my ( $self, $data ) = @_;

    _check_data( \$data );

    $data = pack 'h*', $data;
    $self->_do_xor( \$data );

    chop $data while substr( $data, -1 ) eq "\0";

    return $data;
}

sub _do_xor {
    my ( $self, $data_ref ) = @_;

    #The bit-xor logic below needs to use $secret as a string, not as a number.
    #NB: This appears to be one of the few times where Perl really does care
    #whether a scalar is a string or a number...
    my $secret = q<> . $self->{'secret'};

    my $c           = 0;
    my $data_length = length $$data_ref;
    while ( $c < ($data_length) - 1 ) {
        substr( $$data_ref, $c, length $secret ) ^= $secret;
        $c += length $secret;
    }

    return 1;
}

1;
